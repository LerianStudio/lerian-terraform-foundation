terraform {
  # 1.7.0, not the 1.5.0 the rest of this tree carries: tests/ uses mock_provider
  # and override_data, and `terraform validate` PARSES tests/*.tftest.hcl. Same
  # floor and reason as products/iam/github-oidc-s3-upload.
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.42.0, < 7.0.0"
    }
  }
}
