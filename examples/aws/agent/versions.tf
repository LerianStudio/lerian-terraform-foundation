# Terraform and provider version constraints
terraform {
  # 1.4 rather than the 1.0 the older roots here declare: this one uses
  # terraform_data, which arrived in 1.4, and preconditions, which arrived in
  # 1.2. A 1.0 that is admitted by the constraint cannot validate the code.
  required_version = ">= 1.4"

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
