# Plans a dedicated prd group under mocks. The assertion that its parameter group
# carries maxmemory-policy = noeviction lives in scripts/test-cost-tags.py: the
# group is a nested module resource, which tftest assertions cannot address.

mock_provider "aws" {
  mock_data "aws_vpc" {
    defaults = { id = "vpc-12345678", cidr_block = "10.0.0.0/16" }
  }
  mock_data "aws_subnets" {
    defaults = { ids = ["subnet-12345678", "subnet-87654321"] }
  }
}

mock_provider "random" {}

run "dedicated_prd" {
  command = plan

  variables {
    environment                            = "prd"
    allow_private_subnet_cidr_ingress      = false
    eks_node_security_group_lookup_enabled = false
    allowed_cidr_blocks                    = ["10.0.0.0/16"]
  }
}
