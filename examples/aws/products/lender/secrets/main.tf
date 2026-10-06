################################################################################
# products/lender/secrets — the vault identity of the lender
#
# The lender reads its per-tenant M2M credential for each service it calls —
# midaz, consignado-gateway, matcher — by GetSecretValue at
#
#   tenants/{ENV_NAME}/{tenantOrgID}/lender/m2m/{target}/credentials
#
# (lib-commons commons/secretsmanager/m2m.go GetM2MCredentials; "lender" is the
# service's constants.ApplicationName). It is a BOOT requirement once the Midaz
# relay is configured: an unreadable credential stops the process instead of
# letting posting intents pile up in the outbox. The tenant segment is a
# wildcard, so the allow is tenants/{env}/*/lender/m2m/* — every tenant's lender
# credentials and no other service's.
#
# THE PREFIX IS DERIVED FROM app_env_name, never typed in a tfvars. A vault
# prefix that disagrees with the ENV_NAME the pod boots with matches nothing, and
# the lender reports a missing credential rather than a permission problem.
#
# THE CUSTODY DENY IS A LITERAL, NOT A VARIABLE. tenants/*/*/*/external/ holds a
# tenant's Dataprev credential and only br-consignado-gw may read it. The allow
# does not reach it; the Deny keeps that true whatever is attached to this role
# later, and a variable is something a tfvars can empty.
#
# No ListSecrets, no writes and no KMS grant: the lender knows every path it
# reads, and tenant-manager writes those credentials under the AWS-managed key.
#
# Deploy order: infra-base/eks -> this stack. The OIDC lookup is SINGULAR and fails
# the plan when the cluster does not exist.
################################################################################

module "network" {
  source = "../../../_modules/product-network"

  enabled     = false
  environment = var.environment

  eks_cluster_name = var.eks_cluster_name
}

locals {
  lookup_oidc_provider = var.oidc_provider_arn == ""

  oidc_provider_arn = var.oidc_provider_arn != "" ? var.oidc_provider_arn : one(data.aws_iam_openid_connect_provider.cluster[*].arn)
}

data "aws_eks_cluster" "cluster" {
  count = local.lookup_oidc_provider ? 1 : 0

  name = module.network.eks_cluster_name
}

data "aws_iam_openid_connect_provider" "cluster" {
  count = local.lookup_oidc_provider ? 1 : 0

  url = data.aws_eks_cluster.cluster[0].identity[0].oidc[0].issuer
}

module "secrets" {
  source = "../../../_modules/irsa-secretsmanager"

  product     = var.product
  environment = var.environment
  extra_tags  = var.extra_tags

  oidc_provider_arn = local.oidc_provider_arn
  service_account   = var.service_account

  secret_path_prefixes = ["tenants/${var.app_env_name}/*/lender/m2m/"]

  # The only call lib-commons makes on the M2M path.
  read_actions = ["secretsmanager:GetSecretValue"]

  deny_secret_path_patterns = ["tenants/*/*/*/external/"]
}
