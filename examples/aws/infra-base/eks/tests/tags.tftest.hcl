mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
      arn        = "arn:aws:iam::123456789012:role/test"
    }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws", dns_suffix = "amazonaws.com" }
  }
  mock_data "aws_iam_session_context" {
    defaults = { issuer_arn = "arn:aws:iam::123456789012:role/test" }
  }
  mock_data "aws_vpc" {
    defaults = { id = "vpc-12345678", cidr_block = "10.0.0.0/16" }
  }
  mock_data "aws_subnets" {
    defaults = { ids = ["subnet-12345678", "subnet-87654321"] }
  }
}
mock_provider "tls" {}
mock_provider "time" {}
mock_provider "cloudinit" {}
mock_provider "null" {}

run "cost_tags" {
  command = plan

  variables {
    environment = "dev"
    extra_tags  = { CostCenter = "test-cost-center", Project = "test-project" }
    node_groups = {
      default = { tags = { Owner = "test-owner" } }
      batch   = { tags = { Owner = "batch-owner", CostCenter = "batch-cost-center" } }
    }
  }

  assert {
    condition     = module.naming.tags.CostCenter == "test-cost-center"
    error_message = "EKS must accept cost tags through naming."
  }
}
