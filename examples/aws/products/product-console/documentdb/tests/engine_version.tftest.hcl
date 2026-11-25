# Plans a dedicated dev cluster under mocks. The assertion that the cluster is
# planned with engine_version = "5.0.0" when the caller leaves it null lives in
# scripts/test-cost-tags.py: the cluster is a nested module resource, which
# tftest assertions cannot address.
#
# The two failure runs point `module` at _modules/mongodb-documentdb directly:
# expect_failures only accepts objects of the module under test, never
# module.documentdb.* of this root.

mock_provider "aws" {
  mock_data "aws_vpc" {
    defaults = { id = "vpc-12345678", cidr_block = "10.0.0.0/16" }
  }
  mock_data "aws_subnets" {
    defaults = { ids = ["subnet-12345678", "subnet-87654321"] }
  }
  # The CMK module renders its key policy from this document; the mock's random
  # string would fail the provider's JSON check on aws_kms_key.policy.
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012", arn = "arn:aws:iam::123456789012:user/test" }
  }
}

mock_provider "random" {}

variables {
  environment                            = "dev"
  allow_private_subnet_cidr_ingress      = false
  eks_node_security_group_lookup_enabled = false
  allowed_cidr_blocks                    = ["10.0.0.0/16"]
}

# engine_version left null: derived from docdb5.0 (checked in test-cost-tags.py).
run "derived_from_family" {
  command = plan
}

run "pinned_matching_family" {
  command = plan

  variables {
    engine_version = "5.0.0"
  }
}

run "pinned_mismatching_family" {
  command = plan

  variables {
    product        = "product-console"
    engine_version = "4.0.0"
  }

  module {
    source = "../../../_modules/mongodb-documentdb"
  }

  expect_failures = [aws_docdb_cluster.main]
}

run "invalid_family" {
  command = plan

  variables {
    product                = "product-console"
    parameter_group_family = "mongo5.0"
  }

  module {
    source = "../../../_modules/mongodb-documentdb"
  }

  expect_failures = [var.parameter_group_family]
}
