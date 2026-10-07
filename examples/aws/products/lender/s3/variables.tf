################################################################################
# Stack identity
#
# NOTE: there is no `mode` variable here, unlike the datastore roots:
# _modules/s3-bucket has no mode input because object storage has no shared tier
# to resolve.
################################################################################

variable "region" {
  description = "AWS region the buckets are created in. Keep it equal to the region of the sibling datastore roots: the bucket is reached over the regional S3 endpoint and a cross-region bucket pays inter-region transfer on every object."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.region))
    error_message = "The region must be a valid AWS region identifier, e.g. us-east-1 or sa-east-1."
  }
}

variable "product" {
  description = "Product these buckets belong to. Pinned to \"lender\" by validation: the derived bucket name (lender-{env}-{logical}-{account_id}) and policy name (lender-{env}-{logical}-s3-access) are the cross-stack contract products/lender/secrets attaches by."
  type        = string
  default     = "lender"

  validation {
    condition     = var.product == "lender"
    error_message = "The product must be \"lender\". To provision object storage for another product, copy this directory to examples/aws/products/<product>/s3 instead."
  }
}

variable "environment" {
  description = "Deployment environment. One of dev, stg or prd."
  type        = string

  validation {
    condition     = contains(["dev", "stg", "prd"], var.environment)
    error_message = "The environment must be one of: dev, stg, prd."
  }
}

variable "extra_tags" {
  description = "Additional tags merged on top of the standard Lerian tag set (Product, Environment, ManagedBy, Repository)."
  type        = map(string)
  default     = {}
}

################################################################################
# Buckets
#
# Keyed by LOGICAL name. helm_values indexes "issuance-custody", so the key is
# required. Object Lock stays available per bucket and off by default; see the
# header of main.tf.
################################################################################

variable "buckets" {
  description = <<-EOT
    Buckets to create, keyed by LOGICAL name. Each key becomes part of the real
    bucket name: {product}-{environment}-{logical_name}-{account_id}.

    Per bucket options (all optional): versioning_enabled, kms_key_arn,
    force_destroy, object_lock_enabled, object_lock_mode, object_lock_days,
    object_lock_years, lifecycle_enabled, transition_ia_days,
    transition_glacier_days, expiration_days, noncurrent_expiration_days,
    abort_incomplete_multipart_upload_days, cors_rules. See
    _modules/s3-bucket/README.md for the full table and the ordering rules the
    module validates (glacier after IA, expiration after both).

    OBJECT LOCK IS SETTABLE ONLY AT BUCKET CREATION. It cannot be enabled later and
    cannot be disabled once enabled. With it on, the policy withholds
    s3:DeleteObject and the instrument custody sweeper cannot remove orphans.
  EOT

  type = map(object({
    versioning_enabled                     = optional(bool, true)
    kms_key_arn                            = optional(string, null)
    force_destroy                          = optional(bool, false)
    object_lock_enabled                    = optional(bool, false)
    object_lock_mode                       = optional(string, null)
    object_lock_days                       = optional(number, null)
    object_lock_years                      = optional(number, null)
    lifecycle_enabled                      = optional(bool, true)
    transition_ia_days                     = optional(number, null)
    transition_glacier_days                = optional(number, null)
    expiration_days                        = optional(number, null)
    noncurrent_expiration_days             = optional(number, null)
    abort_incomplete_multipart_upload_days = optional(number, 7)
    cors_rules = optional(list(object({
      allowed_headers = optional(list(string), ["*"])
      allowed_methods = list(string)
      allowed_origins = list(string)
      expose_headers  = optional(list(string), [])
      max_age_seconds = optional(number, 3600)
    })), [])
  }))

  default = {
    "issuance-custody" = {}
  }

  validation {
    condition     = contains(keys(var.buckets), "issuance-custody")
    error_message = "The buckets map must contain the key \"issuance-custody\": it is the bucket ISSUANCE_CUSTODY_S3_BUCKET points at, and helm_values indexes it by name. Additional buckets may be added alongside it."
  }
}

variable "transition_ia_storage_class" {
  description = "Storage class used by transition_ia_days. Passed through to the module."
  type        = string
  default     = "STANDARD_IA"
}

variable "transition_glacier_storage_class" {
  description = "Storage class used by transition_glacier_days. Passed through to the module."
  type        = string
  default     = "GLACIER"
}

variable "require_latest_tls_policy" {
  description = "Additionally deny requests negotiating a TLS version older than 1.2. The policy denying plain HTTP is always attached by the module and is not optional."
  type        = bool
  default     = true
}

################################################################################
# IRSA
################################################################################

variable "irsa_enabled" {
  description = "Create an IAM role of this root's own for the lender pod. FALSE (the default) emits the per-bucket IAM policies only: products/lender/secrets attaches them to lender-{env}-secrets-irsa, because a ServiceAccount carries one role-arn annotation. TRUE adds a singular OIDC lookup that fails the plan when infra-base/eks does not exist."
  type        = bool
  default     = false
}

variable "oidc_provider_arn" {
  description = "ARN of the EKS cluster IAM OIDC provider. Leave EMPTY (the default) to derive it: the cluster name comes from module.network, data \"aws_eks_cluster\" reads its issuer URL and data \"aws_iam_openid_connect_provider\" turns that into the ARN. Set it explicitly only to point at a cluster this repository did not create — an explicit value skips both lookups entirely, which also makes the plan work with no EKS read permissions."
  type        = string
  default     = ""
}

variable "service_account" {
  description = "Kubernetes service account allowed to assume the IRSA role, in \"namespace:name\" form. Read only when irsa_enabled is true. The default is what helm-internal charts/lender renders with no override, the same value products/lender/secrets pins its trust policy to."
  type        = string
  default     = "lender:lender"

  validation {
    condition     = var.service_account == "" || can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?:[a-z0-9]([a-z0-9.-]*[a-z0-9])?$", var.service_account))
    error_message = "The service_account must be in \"namespace:name\" form, e.g. \"lender:lender\"."
  }
}

################################################################################
# Cross-stack context
################################################################################

variable "eks_cluster_name" {
  description = "Name of the EKS cluster whose OIDC provider is resolved. Leave empty (the default) to DERIVE \"lerian-{environment}-eks\" — the cluster belongs to infra-base and carries the \"lerian\" product label, NOT this product's."
  type        = string
  default     = ""
}
