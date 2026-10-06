output "mode" {
  description = "Published as a constant so `terraform output mode` answers uniformly across every root of this product. An IAM role has no shared tier."
  value       = "dedicated"
}

output "eks_cluster_name" {
  description = "EKS cluster whose OIDC provider backs the role, as derived or overridden."
  value       = module.network.eks_cluster_name
}

output "oidc_provider_arn" {
  description = "OIDC provider the trust policy federates to."
  value       = local.oidc_provider_arn
}

output "iam_role_arn" {
  description = "THE HANDOFF VALUE. Goes on the lender ServiceAccount as eks.amazonaws.com/role-arn."
  value       = module.secrets.iam_role_arn
}

output "iam_role_name" {
  description = "Name of the IRSA role, lender-{env}-secrets-irsa."
  value       = module.secrets.iam_role_name
}

output "iam_policy_arn" {
  description = "ARN of the policy attached to the role."
  value       = module.secrets.iam_policy_arn
}

output "service_account" {
  description = "The namespace:name the trust policy is pinned to."
  value       = module.secrets.service_account
}

output "secret_arn_patterns" {
  description = "Resource ARN patterns the policy was rendered with. Read this before debugging a lender that will not boot over a missing M2M credential: a prefix whose environment segment differs from the pod's ENV_NAME looks identical to a credential that was never written."
  value       = module.secrets.secret_arn_patterns
}

################################################################################
# Helm handoff
#
# Dotted value paths of helm-internal charts/lender (lender-helm 4.0.1,
# values.yaml: lender.configmap at :494, lender.serviceAccount at :788), not bare
# env var names: the chart exists, so the handoff names where the value goes.
#
# AWS_REGION is emitted because the chart defaults it to us-east-1. A lender
# reading its credential from the wrong region gets ResourceNotFound and reports
# the credential missing, which sends the reader to the vault instead of here.
################################################################################

output "helm_values" {
  description = "Lender chart values this role fills in. ENV_NAME must stay equal to app_env_name — the vault prefix was built from it."
  value = {
    "lender.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn" = module.secrets.iam_role_arn
    "lender.configmap.ENV_NAME"                                        = var.app_env_name
    "lender.configmap.AWS_REGION"                                      = var.region
  }
}
