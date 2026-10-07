################################################################################
# Outputs
#
# No endpoint, no port, no secret: S3 is a regional API endpoint reached by IAM
# rather than a host inside the VPC. The `mode` output is published as a
# constant so `terraform output mode` answers uniformly across every root.
################################################################################

output "mode" {
  description = "Published as a constant. Object storage has no shared tier: a bucket costs nothing when empty and its contents belong to exactly one product."
  value       = "dedicated"
}

output "eks_cluster_name" {
  description = "EKS cluster whose OIDC provider backs the IRSA role, as derived or overridden."
  value       = module.network.eks_cluster_name
}

################################################################################
# The bucket
################################################################################

output "bucket_name" {
  description = "Name of the lender custody bucket. THIS IS THE ISSUANCE_CUSTODY_S3_BUCKET VALUE."
  value       = module.storage.bucket_names["issuance-custody"]
}

output "bucket_arn" {
  description = "ARN of the custody bucket."
  value       = module.storage.bucket_arns["issuance-custody"]
}

output "bucket_regional_domain_name" {
  description = "Regional domain name of the custody bucket."
  value       = module.storage.bucket_regional_domain_names["issuance-custody"]
}

output "bucket_names" {
  description = "Every bucket this root created, by logical name."
  value       = module.storage.bucket_names
}

output "bucket_arns" {
  description = "Every bucket ARN, by logical name."
  value       = module.storage.bucket_arns
}

################################################################################
# IRSA
################################################################################

output "iam_role_arn" {
  description = "ARN of this root's own IRSA role. Null with irsa_enabled = false, the estate's mode: the lender's role comes from products/lender/secrets."
  value       = module.storage.iam_role_arn
}

output "iam_role_name" {
  description = "Name of this root's own IRSA role. Null unless irsa_enabled is true."
  value       = module.storage.iam_role_name
}

output "iam_policy_arns" {
  description = "Per-bucket IAM policy ARNs. products/lender/secrets attaches the issuance-custody one to lender-{env}-secrets-irsa by name, through additional_policy_names."
  value       = module.storage.iam_policy_arns
}

output "oidc_provider_arn" {
  description = "OIDC provider the trust policy federates to. Empty with irsa_enabled = false."
  value       = local.oidc_provider_arn
}

output "service_account" {
  description = "The namespace:name the trust policy is pinned to. Empty with irsa_enabled = false."
  value       = local.service_account
}

################################################################################
# Helm handoff
#
# Dotted value paths of helm-internal charts/lender, whose ConfigMap renders
# every lender.configmap key verbatim. ISSUANCE_CUSTODY_S3_REGION is emitted
# because the lender builds this client with that region explicitly and
# defaults it to us-east-1; it is a key of its own, distinct from the
# AWS_REGION products/lender/secrets emits.
################################################################################

output "helm_values" {
  description = "Lender chart values this bucket fills in."
  value = {
    "lender.configmap.ISSUANCE_CUSTODY_S3_BUCKET" = module.storage.bucket_names["issuance-custody"]
    "lender.configmap.ISSUANCE_CUSTODY_S3_REGION" = var.region
  }
}
