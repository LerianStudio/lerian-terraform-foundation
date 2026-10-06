variable "region" {
  description = "AWS region the role is created in. IAM is global, but the secret ARNs the policy scopes to are regional, so this must be the region the vault lives in."
  type        = string
  default     = "us-east-1"
}

variable "product" {
  description = "Pinned to \"lender\": the derived role name, lender-{env}-secrets-irsa, is the cross-stack discovery contract."
  type        = string
  default     = "lender"

  validation {
    condition     = var.product == "lender"
    error_message = "This stack is lender. A second product gets its own directory under examples/aws/products."
  }
}

variable "environment" {
  description = "Deployment environment. One of dev, stg or prd. NAMES THE IAM OBJECTS ONLY — the environment segment inside the vault paths is the application's ENV_NAME, app_env_name."
  type        = string
}

variable "extra_tags" {
  description = "Additional tags merged on top of the standard Lerian tag set."
  type        = map(string)
  default     = {}
}

variable "eks_cluster_name" {
  description = "EKS cluster whose OIDC provider backs the role. Leave empty (the default) to DERIVE \"lerian-{environment}-eks\" — the cluster belongs to infra-base and carries the \"lerian\" product label."
  type        = string
  default     = ""
}

variable "oidc_provider_arn" {
  description = "Escape hatch overriding the OIDC provider lookup. Empty (the default) derives it from the cluster name."
  type        = string
  default     = ""
}

variable "service_account" {
  description = "Kubernetes service account the role is pinned to, \"namespace:name\". The default is what helm-internal charts/lender renders with no override: namespaceOverride \"lender\", and a ServiceAccount named after lender.fullname, which nameOverride makes \"lender\". A release that overrides either needs the same value here, or the :sub condition admits no pod."
  type        = string
  default     = "lender:lender"
}

variable "app_env_name" {
  description = <<-EOT
    The APPLICATION's environment name — the ENV_NAME the lender boots with, and
    the segment the vault prefix is built from. "production" on this estate,
    while var.environment is "prd". They are different vocabularies and both are
    load-bearing: var.environment names the IAM objects, this names the vault.

    Credentials are written under it by tenant-manager, so it must match what
    the vault already holds; nothing re-derives it.
  EOT

  type    = string
  default = "production"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*$", var.app_env_name))
    error_message = "The app_env_name must be a lowercase name, e.g. production."
  }
}
