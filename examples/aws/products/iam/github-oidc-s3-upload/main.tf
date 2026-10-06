################################################################################
# products/iam/github-oidc-s3-upload — the identities release pipelines use to
# publish migrations into this account's migrations bucket
#
# The tenant manager reads a service's SQL migrations out of an S3 bucket in the
# APPLICATION account, under {channel}/{service}/{module}/{dbType}/. The files
# get there from the service's release pipeline: go-release's `S3 Upload` job
# copies them on every tag. That job authenticates by asking GitHub for a fresh
# OIDC token and calling sts:AssumeRoleWithWebIdentity — so the principal a trust
# policy must name is GITHUB'S OIDC PROVIDER, not a role in another AWS account.
#
# Three parts, all of them load-bearing:
#
#   1. GitHub's OIDC issuer, registered ONCE as an identity provider in THIS
#      account, so a token minted by GitHub Actions is a principal this account
#      recognises at all;
#   2. per listed repository, a role whose trust policy pins `:sub` to TAG
#      pushes of THAT repository and `:aud` to sts.amazonaws.com;
#   3. per role, one inline policy with s3:PutObject over exactly the prefixes
#      that repository publishes to.
#
# ONE ROLE PER REPOSITORY, NOT ONE ROLE FOR ALL. A role's permissions cannot
# tell which repository assumed it: GitHub's token carries no session tags, and
# :sub is visible to the trust policy only. A shared role would hand every
# listed repository the union of the prefixes, so one release could overwrite
# another service's migrations, which the tenant manager then runs against that
# service's database. The provider is shared because AWS allows one per URL per
# account; everything after it is per repository.
#
# THE ROLES LIVE IN THE ACCOUNT THAT OWNS THE BUCKET, which is what makes a
# bucket policy unnecessary: an in-account role with s3:PutObject is sufficient,
# and _modules/s3-bucket does not have to grow a bucket-policy input.
#
# WHY IT LIVES UNDER products/ WHEN IT IS NOT A PRODUCT. lerian-infra discovers
# roots by walking products/*/* and nothing else, and its infra-base stage is
# hardcoded to exactly vpc and eks. A root outside that shape has no target, no
# ordering, no state key and no account guard. Precedent:
# products/iam/oidc-cross-account-role, products/lerian-platform/dns.
#
# Deploy order: the bucket first (products/tenant-manager/s3, here), then this
# root, then the `aws_role_arn` entry in each repository's release.yml. Until
# that last step lands for a repository, NOTHING assumes its role.
################################################################################

module "naming" {
  source = "../../../_modules/naming"

  # "lerian", not a repository: the identity provider is an account singleton
  # every role below trusts, and no one repository owns it.
  product     = "lerian"
  environment = var.environment
  component   = "migrations-upload"
  extra_tags  = var.extra_tags
}

# Partition rather than a literal "aws": the same ARNs have to render correctly in
# GovCloud and China, where the partition is aws-us-gov / aws-cn.
data "aws_partition" "current" {}

locals {
  ##############################################################################
  # The channel folders — DERIVED, NEVER AN INPUT
  #
  # go-release picks the top-level folder from the tag's channel, and the
  # mapping is its code, not a preference of this estate:
  #
  #   *-beta*                      -> development/
  #   *-rc*                        -> staging/
  #   ^v[0-9]+\.[0-9]+\.[0-9]+$    -> production/
  #
  # An `s3_uploads` entry is NOT conditional on the channel: it runs on every tag
  # the repository cuts. A service that cuts a beta on each merge to develop
  # therefore writes to development/ constantly, and a policy listing only
  # production/ turns every one of those merges into a red `S3 Upload` job — the
  # step runs under `set -euo pipefail`, so one AccessDenied kills the job.
  #
  # Listing the three in a tfvars would make "all the channels, and only the
  # channels" a thing somebody has to remember. Deriving them here makes it true
  # by construction, and the cost of the two folders nothing reads today is zero.
  ##############################################################################
  channel_folders = ["development", "staging", "production"]

  # ONE definition per repository of the subject and the prefixes, read by the
  # documents attached below AND by the outputs that report them. Two copies
  # would be two things to keep equal, and the outputs are what an apply's
  # evidence gets read off.
  #
  # {channel}/{service}/* — one IAM wildcard, and it crosses "/", so the module
  # and dbType segments go-release appends (br-consignado-gw/consignado/
  # postgresql/…) are covered at any depth.
  uploads = {
    for repository, upload in var.github_repositories : repository => {
      role_name     = upload.role_name
      trust_subject = "repo:${repository}:ref:refs/tags/*"
      object_prefix_arns = flatten([
        for channel in local.channel_folders : [
          for service in upload.services :
          "arn:${data.aws_partition.current.partition}:s3:::${var.migrations_bucket_name}/${channel}/${service}/*"
        ]
      ])
    }
  }
}

################################################################################
# GitHub's OIDC issuer, registered in this account
#
# NO thumbprint_list. Since 2023 AWS validates token.actions.githubusercontent.com
# against its own trust store and ignores whatever thumbprint is recorded; pinning
# GitHub's intermediate CA fingerprint here would be a value that means nothing,
# rots on rotation, and reads as a security control.
#
# ONE PER ACCOUNT. AWS refuses a second provider for the same URL
# (EntityAlreadyExists), which is why a second repository is a new entry in
# github_repositories rather than a second instance of this root.
################################################################################

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  tags = merge(module.naming.tags, { Name = "${module.naming.name}-oidc" })
}

################################################################################
# Trust policy
#
# :sub IS THE BOUNDARY AND IT IS FAIL-CLOSED ON TAGS. Every GitHub Actions token
# in the world carries the same issuer, so :sub is the only thing keeping other
# repositories out. StringLike rather than StringEquals because the tag name is
# part of the subject and changes on every release — the wildcard is on the tag,
# never on the repository.
#
#   repo:OWNER/REPO:ref:refs/tags/v3.0.0-rc.9   admitted by REPO's role only
#   repo:OWNER/REPO:ref:refs/heads/develop      REFUSED (a branch push is a
#                                               different subject entirely)
#   repo:OWNER/REPO:pull_request                REFUSED
#   repo:OTHER/REPO:ref:refs/tags/v1.0.0        REFUSED by every role
#
# The branch case is the one that matters: a workflow run from a pull request of
# a fork cannot mint a token this role accepts, so a contributor cannot reach the
# bucket by editing a workflow file.
#
# :aud pins sts.amazonaws.com, the audience go-release requests. The provider's
# client_id_list already requires it, so a token minted for another audience is
# refused before any condition is read; it is written out because AWS documents
# pinning both for web-identity trust, and because a second audience added to
# client_id_list later would otherwise widen every role silently.
#
# jsonencode rather than aws_iam_policy_document: a data source is a provider
# round trip, so under mock_provider the rendered document is generated noise and
# the trust — the whole security boundary of this root — could not be asserted
# in tests/reach_and_subject.tftest.hcl at all.
################################################################################

resource "aws_iam_role" "this" {
  for_each = local.uploads

  name        = each.value.role_name
  description = "Release pipeline of ${each.key} publishing migrations to s3://${var.migrations_bucket_name}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowRepositoryTagPushToAssumeRole"
      Effect = "Allow"
      Action = "sts:AssumeRoleWithWebIdentity"

      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }

      Condition = {
        StringLike = {
          "token.actions.githubusercontent.com:sub" = each.value.trust_subject
        }
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
  force_detach_policies = true

  # The AWS default (1 hour), written out because it is the ceiling on a
  # credential handed to a CI runner. Raising it would not make an upload more
  # reliable: the job finishes in seconds, so a longer session only lengthens the
  # window in which a leaked credential still works.
  max_session_duration = 3600

  tags = merge(module.naming.tags, { Name = each.value.role_name })
}

################################################################################
# Grants — one inline policy per role, one verb
#
# INLINE and not managed: an inline policy cannot be attached to a second
# principal, and deleting the role deletes it too, with no orphan left behind for
# something else to pick up.
#
# NO s3:DeleteObject, and this is a correctness constraint rather than a taste.
# The tenant manager decides what to run by comparing the migrations a tenant has
# APPLIED against the ones AVAILABLE in the bucket. Removing a .sql a tenant
# already applied puts a hole in that comparison. A release pipeline only ever
# adds files, so it never needs to remove one.
#
# NO s3:ListBucket either: go-release copies each file by key. Listing is the
# reader's job, and the reader is not this identity.
################################################################################

resource "aws_iam_role_policy" "upload" {
  for_each = local.uploads

  name = "${each.value.role_name}-policy"
  role = aws_iam_role.this[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "PutMigrationObjects"
      Effect   = "Allow"
      Action   = "s3:PutObject"
      Resource = each.value.object_prefix_arns
    }]
  })
}
