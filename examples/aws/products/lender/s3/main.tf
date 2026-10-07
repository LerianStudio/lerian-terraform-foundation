################################################################################
# products/lender/s3 — the lender's own custody bucket
#
# One bucket, ISSUANCE_CUSTODY_S3_BUCKET, holding three disjoint key namespaces
# under the tenant prefix lib-commons tenant-manager/s3 applies from the request
# context:
#
#   {tenantId}/instruments/...          rendered credit instruments (CCB PDFs)
#   {tenantId}/assignment-dossiers/...  cessão receivable dossiers
#   {tenantId}/assignment-terms/...     assignment (endorsement) terms
#
# An empty ISSUANCE_CUSTODY_S3_BUCKET leaves all three dormant: the routes stay
# mounted and answer 503, never a document emitted without custody.
#
# THE CALLS. PutObject (plain, no retention headers), GetObject, and, only when
# JOBS_INSTRUMENT_CUSTODY_SWEEP_ENABLED is on, ListObjectsV2 + DeleteObject on
# the instruments/ prefix to remove PII-bearing orphans no row references.
# _modules/s3-bucket grants exactly that set, and DeleteObject only while
# Object Lock is off.
#
# NO OBJECT LOCK BY DEFAULT. The lender asserts nothing about retention at boot,
# rewrites the same key on a crash retry, and its sweeper exists to delete
# orphans. Object Lock is settable only at bucket creation and cannot be
# removed: enabling it is a retention decision for these documents, made in the
# tfvars before the first apply, and it withholds the sweeper's DeleteObject.
#
# ONE ROLE. irsa_enabled defaults to false: this root emits the attachable
# policy and products/lender/secrets attaches it to lender-{env}-secrets-irsa,
# because a ServiceAccount carries one role-arn annotation. Apply this root
# first. With irsa_enabled = true the OIDC lookup below is singular and fails
# the plan when infra-base/eks does not exist.
################################################################################

module "network" {
  source = "../../../_modules/product-network"

  enabled     = false
  environment = var.environment

  eks_cluster_name = var.eks_cluster_name
}

locals {
  lookup_oidc_provider = var.irsa_enabled && var.oidc_provider_arn == ""

  oidc_provider_arn = var.irsa_enabled ? (
    var.oidc_provider_arn != "" ? var.oidc_provider_arn : one(data.aws_iam_openid_connect_provider.cluster[*].arn)
  ) : ""

  service_account = var.irsa_enabled ? var.service_account : ""
}

data "aws_eks_cluster" "cluster" {
  count = local.lookup_oidc_provider ? 1 : 0

  name = module.network.eks_cluster_name
}

data "aws_iam_openid_connect_provider" "cluster" {
  count = local.lookup_oidc_provider ? 1 : 0

  url = data.aws_eks_cluster.cluster[0].identity[0].oidc[0].issuer
}

module "storage" {
  source = "../../../_modules/s3-bucket"

  product     = var.product
  environment = var.environment
  extra_tags  = var.extra_tags

  buckets = var.buckets

  transition_ia_storage_class      = var.transition_ia_storage_class
  transition_glacier_storage_class = var.transition_glacier_storage_class
  require_latest_tls_policy        = var.require_latest_tls_policy

  oidc_provider_arn = local.oidc_provider_arn
  service_account   = local.service_account
}
