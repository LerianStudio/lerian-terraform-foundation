# Plans a dedicated dev cluster under mocks. The assertions on the planned
# engine_version live in scripts/test-cost-tags.py: the cluster is a nested
# module resource, which tftest assertions cannot address. That check reads
# each run's plan by run name:
#   pinned_like_tfvars_example -> "5.0.0"
#   later_patch                -> "5.0.2"
#   null_sends_no_version      -> unset (no derivation from the family, so
#                                 existing clusters never plan a downgrade)
#
# The failure runs point `module` at _modules/mongodb-documentdb directly:
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
  parameter_group_family                 = "docdb5.0"
  engine_version                         = "5.0.0"
}

# What envs/*.tfvars-example now carry.
run "pinned_like_tfvars_example" {
  command = plan
}

# Any patch of the family's major.minor is accepted.
run "later_patch" {
  command = plan

  variables {
    engine_version = "5.0.2"
  }
}

# Null must reach the provider as null: AWS keeps an existing cluster's version.
run "null_sends_no_version" {
  command = plan

  variables {
    engine_version = null
  }
}

run "pinned_mismatching_family" {
  command = plan

  module {
    source = "../../../_modules/mongodb-documentdb"
  }

  variables {
    product        = "product-console"
    engine_version = "4.0.0"
  }

  expect_failures = [aws_docdb_cluster.main]
}

run "invalid_family" {
  command = plan

  module {
    source = "../../../_modules/mongodb-documentdb"
  }

  variables {
    product                = "product-console"
    parameter_group_family = "mongo5.0"
    engine_version         = null
  }

  expect_failures = [var.parameter_group_family]
}
