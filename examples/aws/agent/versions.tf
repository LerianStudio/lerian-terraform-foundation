# Terraform and provider version constraints
terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    # 3.x: helm 3.0 moved the provider's own configuration under a `kubernetes`
    # attribute and dropped the 2.x block form, so a root written for one does
    # not validate against the other.
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
  }
}
