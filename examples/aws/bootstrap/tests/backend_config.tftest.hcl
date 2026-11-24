mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
      arn        = "arn:aws:sts::123456789012:assumed-role/Admin/alice@example.com"
    }
  }

  # apply validates the bucket policy as JSON; the mock's random string is not.
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

mock_provider "local" {}

variables {
  environment          = "dev"
  region               = "us-east-2"
  write_backend_config = true
}

run "dynamodb_by_default" {
  command = apply

  assert {
    condition = (
      strcontains(local_file.backend_config[0].content, "dynamodb_table = \"lerian-tfstate-lock-dev\"\n") &&
      !strcontains(local_file.backend_config[0].content, "use_lockfile") &&
      strcontains(local_file.backend_config[0].content, "region  = \"us-east-2\"\n") &&
      strcontains(local_file.backend_config[0].content, "encrypt = true\n")
    )
    error_message = "With the default state_lock the backend file must keep dynamodb_table and carry no use_lockfile."
  }
}

run "both_during_the_migration" {
  command = apply
  variables { state_lock = "both" }

  assert {
    condition = (
      strcontains(local_file.backend_config[0].content, "dynamodb_table = \"lerian-tfstate-lock-dev\"\n") &&
      strcontains(local_file.backend_config[0].content, "use_lockfile = true\n")
    )
    error_message = "state_lock = both must set dynamodb_table and use_lockfile together."
  }
}

run "lockfile_only" {
  command = apply
  variables { state_lock = "lockfile" }

  assert {
    condition = (
      strcontains(local_file.backend_config[0].content, "use_lockfile = true\n") &&
      !strcontains(local_file.backend_config[0].content, "dynamodb_table")
    )
    error_message = "state_lock = lockfile must drop dynamodb_table."
  }
}

run "reject_unknown_state_lock" {
  command = plan
  variables { state_lock = "s3" }
  expect_failures = [var.state_lock]
}
