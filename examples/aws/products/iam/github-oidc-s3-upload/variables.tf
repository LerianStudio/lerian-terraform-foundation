variable "region" {
  description = "AWS region the role is created in. IAM is global, but the region selects the endpoint and appears in the ARNs of everything the attached policy scopes to. S3 bucket ARNs carry no region, so this value reaches only the provider and the tags."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.region))
    error_message = "The region must be a valid AWS region identifier, e.g. sa-east-1."
  }
}

variable "environment" {
  description = "Deployment environment this apply belongs to. One of dev, stg or prd; it feeds tags and the state key's backend config. ONE role per repository serves EVERY release channel, so this root is applied only as \"prd\" — the roles are a property of the account that owns the bucket, not of a stack. The channel (development/staging/production) is a FOLDER inside the bucket, chosen by the release pipeline from the tag, never by a second apply."
  type        = string

  validation {
    condition     = var.environment == "prd"
    error_message = "environment must be prd because these account-level roles are deployed once."
  }
}

variable "extra_tags" {
  description = "Additional tags merged on top of the standard Lerian tag set."
  type        = map(string)
  default     = {}
}

################################################################################
# Trust — who may assume which role
################################################################################

variable "github_repositories" {
  description = <<-EOT
    The repositories whose release pipelines may upload, keyed by `owner/repo`.
    One role per entry, all of them trusting the one GitHub identity provider
    this root registers:

      github_repositories = {
        "LerianStudio/br-consignado-gw" = {
          role_name = "consignado-github-oidc-s3-upload"
          services  = ["br-consignado-gw"]
        }
        "LerianStudio/midaz" = {
          role_name = "midaz-github-oidc-s3-upload"
          services  = ["ledger"]
        }
      }

    The KEY and `refs` become that role's `:sub` condition, one
    `repo:{owner}/{repo}:ref:{ref}` per ref, and they are the whole boundary:
    every GitHub Actions token in existence is signed by the same issuer, so
    without `:sub` any workflow on GitHub could assume the role.

    `refs` are the git refs whose workflow runs may upload: `refs/heads/<branch>`
    admits that one branch, `refs/tags/*` admits every tag. Defaults to
    `["refs/tags/*"]`; `["refs/heads/main", "refs/heads/release-candidate"]`
    admits only code merged into those two branches.

    `services` are the `{service}` folders go-release writes that repository's
    migrations under, `{channel}/{service}/{module}/{dbType}/`. Usually the repo
    name, NOT always: Midaz publishes as `ledger`. A list because one repository
    can publish several services.

    `role_name` is copied verbatim into that repository's release workflow, as
    the `aws_role_arn` of an `s3_uploads` entry: a rename here breaks that
    workflow, and an explicit name makes the coupling visible on both sides.
  EOT

  type = map(object({
    role_name = string
    services  = list(string)
    refs      = optional(list(string), ["refs/tags/*"])
  }))

  # The charset is the boundary: a "*" or "?" in a key would be a wildcard in
  # the :sub condition, admitting other repositories.
  validation {
    condition = alltrue([
      for repository in keys(var.github_repositories) :
      can(regex("^[A-Za-z0-9][A-Za-z0-9-]{0,38}/[a-z0-9]([a-z0-9-]*[a-z0-9])?$", repository))
    ])
    error_message = "Every key of github_repositories must be owner/repo, with a repo segment of lowercase alphanumerics and interior hyphens. The key is interpolated into the :sub condition, where a wildcard character would admit other repositories."
  }

  validation {
    condition = alltrue([
      for repository in values(var.github_repositories) :
      can(regex("^[A-Za-z0-9+=,.@_-]{1,64}$", repository.role_name))
      ]) && (
      length(values(var.github_repositories)[*].role_name) ==
      length(distinct(values(var.github_repositories)[*].role_name))
    )
    error_message = "Every role_name in github_repositories must be 1-64 characters from the IAM name charset [A-Za-z0-9+=,.@_-], and no two repositories may share one: the second role would fail mid-apply with EntityAlreadyExists."
  }

  # Same reason on the object side, plus the separation itself: a service listed
  # under two repositories is a prefix both releases can overwrite.
  validation {
    condition = alltrue([
      for repository in values(var.github_repositories) :
      length(repository.services) > 0 && alltrue([
        for service in repository.services : can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", service))
      ])
      ]) && (
      length(flatten(values(var.github_repositories)[*].services)) ==
      length(distinct(flatten(values(var.github_repositories)[*].services)))
    )
    error_message = "Every repository in github_repositories needs at least one service, each a lowercase folder name with no \"/\" or wildcard, and no service may appear under two repositories: that folder would be writable by both releases, and the tenant manager runs what it finds there against that service's database."
  }

  # Each ref lands in :sub under StringLike, where "*" and "?" are wildcards: the
  # whole tag glob is the only one allowed, and a branch is named in full.
  validation {
    condition = alltrue([
      for repository in values(var.github_repositories) :
      length(repository.refs) > 0 && length(repository.refs) == length(distinct(repository.refs)) && alltrue([
        for ref in repository.refs :
        ref == "refs/tags/*" || can(regex("^refs/heads/[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$", ref))
      ])
    ])
    error_message = "Every refs list in github_repositories must be non-empty with no duplicates, each entry either exactly refs/tags/* or refs/heads/<branch> with a branch name of [A-Za-z0-9._-] segments joined by single \"/\". Each ref is interpolated into the :sub condition, where any other wildcard would admit refs nobody listed."
  }
}

################################################################################
# Reach — what each role may do once assumed
################################################################################

variable "migrations_bucket_name" {
  description = <<-EOT
    Name of the bucket the release pipelines upload migrations to — the bucket
    the tenant manager reads them back from. It lives in THIS account; that is
    what makes a bucket policy unnecessary.

    A name, not an ARN: main.tf builds
    `arn:{partition}:s3:::{name}/{channel}/{service}/*` from it.
  EOT

  type = string

  validation {
    condition = (
      can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.migrations_bucket_name)) &&
      !strcontains(var.migrations_bucket_name, "..") &&
      !can(regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}$", var.migrations_bucket_name))
    )
    error_message = "migrations_bucket_name must be a valid S3 bucket NAME (3-63 characters, lowercase alphanumerics, dots and hyphens), without adjacent periods and not formatted as an IPv4 address — not an ARN or URL."
  }
}
