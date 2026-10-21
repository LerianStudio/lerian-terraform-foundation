mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
      arn        = "arn:aws:sts::123456789012:assumed-role/Admin/alice@example.com"
    }
  }
}

mock_provider "local" {}

variables {
  environment          = "dev"
  write_backend_config = false
}

run "default_tags" {
  command = plan

  assert {
    condition = aws_s3_bucket.tfstate.tags == tomap({
      Product    = "lerian", Environment = "dev", ManagedBy = "terraform",
      Repository = "lerian-terraform-foundation", Name = "lerian-tfstate-dev-123456789012",
      CreatedBy  = "arn:aws:sts::123456789012:assumed-role/Admin/alice@example.com"
    }) && aws_dynamodb_table.tfstate_lock.tags.Name == "lerian-tfstate-lock-dev"
    error_message = "Bootstrap defaults and resource names must remain unchanged."
  }
}

run "reject_product_override" {
  command = plan
  variables { extra_tags = { Product = "other" } }
  expect_failures = [var.extra_tags]
}

run "reject_environment_override" {
  command = plan
  variables { extra_tags = { Environment = "prd" } }
  expect_failures = [var.extra_tags]
}

run "reject_managed_by_override" {
  command = plan
  variables { extra_tags = { ManagedBy = "manual" } }
  expect_failures = [var.extra_tags]
}

run "reject_repository_override" {
  command = plan
  variables { extra_tags = { Repository = "other" } }
  expect_failures = [var.extra_tags]
}

run "cost_tags" {
  command = plan

  variables {
    extra_tags = { CostCenter = "test-cost-center", Project = "test-project" }
  }

  assert {
    condition = alltrue([
      for tags in [aws_s3_bucket.tfstate.tags, aws_dynamodb_table.tfstate_lock.tags] :
      tags.CostCenter == "test-cost-center" && tags.Project == "test-project" &&
      tags.Product == "lerian" && tags.Environment == "dev" &&
      tags.ManagedBy == "terraform" && tags.Repository == "lerian-terraform-foundation"
    ])
    error_message = "Both backend resources must receive cost tags through naming without losing standard tags."
  }
}

run "resource_name_wins" {
  command = plan

  variables {
    extra_tags = { Name = "must-not-override-resource-name" }
  }

  assert {
    condition = (
      aws_s3_bucket.tfstate.tags.Name == "lerian-tfstate-dev-123456789012" &&
      aws_dynamodb_table.tfstate_lock.tags.Name == "lerian-tfstate-lock-dev"
    )
    error_message = "Name must remain resource-derived even when extra_tags supplies it."
  }
}

# CreatedBy answers "who made this backend", so it must be the identity that
# ran bootstrap and nothing a caller can supply. extra_tags flows into the
# naming tags, which the resource's own tags are merged over.
run "created_by_cannot_be_forged" {
  command = plan

  variables {
    extra_tags = { CreatedBy = "somebody-else" }
  }

  assert {
    condition     = aws_s3_bucket.tfstate.tags.CreatedBy == "arn:aws:sts::123456789012:assumed-role/Admin/alice@example.com"
    error_message = "CreatedBy must be the caller's ARN even when extra_tags supplies one."
  }
}
