################################################################################
# The three things that are DERIVED here, and are wrong in ways an apply cannot see
#
# Everything else in this root is a literal somebody can read. These are built
# from inputs, and all of them fail silently:
#
#   1. THE CHANNEL FOLDERS. go-release chooses the top-level folder from the
#      tag's channel — beta -> development/, rc -> staging/, stable ->
#      production/ — and an s3_uploads entry runs on EVERY tag, not on the
#      channel somebody had in mind. A policy missing a channel applies cleanly,
#      reads correct, and turns the `S3 Upload` job red on the first tag of that
#      channel, which for a repository that cuts a beta per merge is every merge.
#      That is not a hypothetical: an earlier cut of this task's design left
#      development/ out.
#
#   2. THE SUBJECTS. `repo:{owner}/{repo}:ref:{ref}`, one per listed ref, is the
#      whole trust boundary of each role. A subject built one segment wrong does
#      not fail the apply: the role exists, and the pipeline gets AccessDenied
#      months later — or, worse, a repository or ref that is not listed gets in.
#
#   3. THE SEPARATION. Several repositories share this root and its identity
#      provider. One repository's release reaching another's prefix could
#      overwrite migrations the tenant manager then runs against a database that
#      is not that repository's.
#
# The runs below pin all three against literals, and then prove the inputs that
# are easy to paste wrong are refused rather than interpolated.
#
# mock_provider: no AWS call, no credential, no state. override_data pins the
# partition the ARNs are built from — without it the mocked value is generated
# and the ARN assertions compare against noise.
################################################################################

mock_provider "aws" {}

override_data {
  target = data.aws_partition.current
  values = {
    partition = "aws"
  }
}

variables {
  region      = "sa-east-1"
  environment = "prd"
  github_repositories = {
    "LerianStudio/br-consignado-gw" = {
      role_name = "consignado-github-oidc-s3-upload"
      services  = ["br-consignado-gw"]
    }
    "LerianStudio/lender" = {
      role_name = "lender-github-oidc-s3-upload"
      services  = ["lender"]
    }
    # The service folder is NOT the repo name here: Midaz publishes as ledger.
    "LerianStudio/midaz" = {
      role_name = "midaz-github-oidc-s3-upload"
      services  = ["ledger"]
    }
  }
  migrations_bucket_name = "tenant-manager-prd-migrations-862902859103"
}

run "each_repository_reaches_only_its_own_prefixes" {
  command = plan

  # Read off the documents ACTUALLY ATTACHED to the roles, not the output. An
  # output is a convenience that a refactor can leave pointing at the old local
  # while the resource takes a new one; the attached policy is the thing that
  # grants. Set EQUALITY, not containment: it proves each role holds all three
  # channels of its own repository AND nothing of the other one.
  assert {
    condition = toset(jsondecode(aws_iam_role_policy.upload["LerianStudio/br-consignado-gw"].policy).Statement[0].Resource) == toset([
      "arn:aws:s3:::tenant-manager-prd-migrations-862902859103/development/br-consignado-gw/*",
      "arn:aws:s3:::tenant-manager-prd-migrations-862902859103/staging/br-consignado-gw/*",
      "arn:aws:s3:::tenant-manager-prd-migrations-862902859103/production/br-consignado-gw/*",
    ])
    error_message = "The gateway's role is not granted exactly {channel}/br-consignado-gw/* over the three channels. A missing channel fails the release job on the first tag of that channel; any other prefix — the lender's above all — lets the gateway's release write migrations the tenant manager runs against another service's database."
  }

  assert {
    condition = toset(jsondecode(aws_iam_role_policy.upload["LerianStudio/lender"].policy).Statement[0].Resource) == toset([
      "arn:aws:s3:::tenant-manager-prd-migrations-862902859103/development/lender/*",
      "arn:aws:s3:::tenant-manager-prd-migrations-862902859103/staging/lender/*",
      "arn:aws:s3:::tenant-manager-prd-migrations-862902859103/production/lender/*",
    ])
    error_message = "The lender's role is not granted exactly {channel}/lender/* over the three channels. go-release appends the module and dbType segments (lender/lender/postgresql/…), so the trailing wildcard is mandatory; any other prefix — the gateway's above all — lets the lender's release overwrite migrations the tenant manager runs against the gateway's database."
  }

  # The folder comes from services, not from the repository name: midaz/ is
  # not a folder anything reads, and granting it would leave ledger/ denied.
  assert {
    condition = toset(jsondecode(aws_iam_role_policy.upload["LerianStudio/midaz"].policy).Statement[0].Resource) == toset([
      "arn:aws:s3:::tenant-manager-prd-migrations-862902859103/development/ledger/*",
      "arn:aws:s3:::tenant-manager-prd-migrations-862902859103/staging/ledger/*",
      "arn:aws:s3:::tenant-manager-prd-migrations-862902859103/production/ledger/*",
    ])
    error_message = "Midaz's role is not granted exactly {channel}/ledger/* over the three channels. Midaz publishes its migrations under the service name ledger, not the repository name, and must reach no other service's folder."
  }

  # ONE VERB per role, and it is not DeleteObject. The tenant manager decides
  # what to run by comparing a tenant's applied migrations against the ones
  # available in the bucket, so removing a .sql a tenant already applied puts a
  # hole in that comparison. A widened action list applies cleanly and is
  # invisible until it is used.
  assert {
    condition = length(aws_iam_role_policy.upload) == 3 && alltrue([
      for policy in aws_iam_role_policy.upload : (
        length(jsondecode(policy.policy).Statement) == 1 &&
        jsondecode(policy.policy).Statement[0].Action == "s3:PutObject" &&
        jsondecode(policy.policy).Statement[0].Effect == "Allow"
      )
    ])
    error_message = "There is not exactly one inline policy per listed repository holding exactly one Allow of s3:PutObject. A release pipeline only ever adds files: s3:DeleteObject would let it remove a migration a tenant already applied, and s3:ListBucket belongs to the reader, which is not this identity."
  }
}

run "only_listed_repositories_can_assume_and_each_only_its_own_role" {
  # apply, not plan, and mock_provider is what makes that free: no AWS call, no
  # credential, no state. It is required because assume_role_policy is built
  # from aws_iam_openid_connect_provider.github.arn, which is unknown until
  # apply — and asserting the trust documents is the whole point of this run.
  command = apply

  # One role per listed repository, and the gateway's keeps the name its
  # release.yml already carries: a rename breaks that workflow on its next tag.
  assert {
    condition = (
      length(aws_iam_role.this) == 3 &&
      aws_iam_role.this["LerianStudio/br-consignado-gw"].name == "consignado-github-oidc-s3-upload" &&
      aws_iam_role.this["LerianStudio/lender"].name == "lender-github-oidc-s3-upload" &&
      aws_iam_role.this["LerianStudio/midaz"].name == "midaz-github-oidc-s3-upload"
    )
    error_message = "There is not exactly one role per listed repository under the name github_repositories gives it. The name is copied verbatim into that repository's release.yml; a rename breaks its upload on the next tag."
  }

  ##############################################################################
  # THE TRUST DOCUMENTS ATTACHED TO THE ROLES, not the allowed_subjects output.
  #
  # The output is an echo of a variable: it stays correct while a document says
  # something else entirely, so a test that reads it proves the variable was
  # interpolated somewhere and nothing about who can assume a role.
  ##############################################################################

  # ONE statement, THIS root's provider, :aud pinned. A second Allow is how a
  # trust policy gets widened without anything in the first one looking wrong;
  # the account also holds three EKS issuers, and trusting one of those would
  # admit cluster workloads instead of a release pipeline.
  assert {
    condition = alltrue([
      for role in aws_iam_role.this : (
        length(jsondecode(role.assume_role_policy).Statement) == 1 &&
        jsondecode(role.assume_role_policy).Statement[0].Principal.Federated == aws_iam_openid_connect_provider.github.arn &&
        jsondecode(role.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:aud"] == "sts.amazonaws.com"
      )
    ])
    error_message = "A trust policy is not exactly one statement federating to this root's GitHub provider with :aud pinned to sts.amazonaws.com under StringEquals."
  }

  # No refs listed: each role admits its OWN repository's tags and nothing else.
  # Equality against literals, so a widened glob, a branch, or another
  # repository's subject fails it.
  assert {
    condition = {
      for repository, role in aws_iam_role.this :
      repository => jsondecode(role.assume_role_policy).Statement[0].Condition.StringLike["token.actions.githubusercontent.com:sub"]
      } == {
      "LerianStudio/br-consignado-gw" = ["repo:LerianStudio/br-consignado-gw:ref:refs/tags/*"]
      "LerianStudio/lender"           = ["repo:LerianStudio/lender:ref:refs/tags/*"]
      "LerianStudio/midaz"            = ["repo:LerianStudio/midaz:ref:refs/tags/*"]
    }
    error_message = "A role without refs does not admit exactly its own repository's tag glob, repo:{owner}/{repo}:ref:refs/tags/*."
  }
}

run "listed_refs_are_the_only_subjects" {
  # apply for the same reason as the run above: the trust document names the
  # provider's ARN, unknown until apply.
  command = apply

  variables {
    github_repositories = {
      "LerianStudio/br-consignado-gw" = {
        role_name = "consignado-github-oidc-s3-upload"
        services  = ["br-consignado-gw"]
        refs      = ["refs/heads/main", "refs/heads/release-candidate"]
      }
      "LerianStudio/lender" = {
        role_name = "lender-github-oidc-s3-upload"
        services  = ["lender"]
        refs      = ["refs/heads/main", "refs/heads/release-candidate", "refs/tags/*"]
      }
    }
  }

  assert {
    condition = jsondecode(aws_iam_role.this["LerianStudio/br-consignado-gw"].assume_role_policy).Statement[0].Condition.StringLike["token.actions.githubusercontent.com:sub"] == [
      "repo:LerianStudio/br-consignado-gw:ref:refs/heads/main",
      "repo:LerianStudio/br-consignado-gw:ref:refs/heads/release-candidate",
    ]
    error_message = "A role listing only main and release-candidate does not admit exactly those two branches. A tag subject left in lets any tag push write migrations."
  }

  assert {
    condition = jsondecode(aws_iam_role.this["LerianStudio/lender"].assume_role_policy).Statement[0].Condition.StringLike["token.actions.githubusercontent.com:sub"] == [
      "repo:LerianStudio/lender:ref:refs/heads/main",
      "repo:LerianStudio/lender:ref:refs/heads/release-candidate",
      "repo:LerianStudio/lender:ref:refs/tags/*",
    ]
    error_message = "A role listing two branches and refs/tags/* does not admit exactly those three subjects."
  }
}

run "non_prd_environment_refused" {
  command = plan

  variables {
    environment = "stg"
  }

  expect_failures = [var.environment]
}

run "owner_without_repository_refused" {
  command = plan

  # An owner alone interpolates into `repo:LerianStudio:ref:refs/tags/*`, a
  # subject no token ever carries — the role would exist and admit nobody — and
  # split()[1] would fail the plan somewhere less legible than here.
  variables {
    github_repositories = {
      "LerianStudio" = {
        role_name = "consignado-github-oidc-s3-upload"
        services  = ["br-consignado-gw"]
      }
    }
  }

  expect_failures = [var.github_repositories]
}

run "wildcard_repository_refused" {
  command = plan

  # `LerianStudio/*` would become `repo:LerianStudio/*:ref:refs/tags/*` and
  # `{channel}/*/*`: every repository of the organisation admitted, reaching
  # every service's migrations.
  variables {
    github_repositories = {
      "LerianStudio/*" = {
        role_name = "consignado-github-oidc-s3-upload"
        services  = ["br-consignado-gw"]
      }
    }
  }

  expect_failures = [var.github_repositories]
}

run "service_under_two_repositories_refused" {
  command = plan

  # ledger/ under both lender and midaz: two releases able to overwrite the same
  # migrations, which is the separation this root exists to keep.
  variables {
    github_repositories = {
      "LerianStudio/lender" = {
        role_name = "lender-github-oidc-s3-upload"
        services  = ["lender", "ledger"]
      }
      "LerianStudio/midaz" = {
        role_name = "midaz-github-oidc-s3-upload"
        services  = ["ledger"]
      }
    }
  }

  expect_failures = [var.github_repositories]
}

run "role_name_under_two_repositories_refused" {
  command = plan

  # A copy-pasted entry: the plan would pass and the second role would fail
  # mid-apply with EntityAlreadyExists, after the first was already created.
  variables {
    github_repositories = {
      "LerianStudio/lender" = {
        role_name = "consignado-github-oidc-s3-upload"
        services  = ["lender"]
      }
      "LerianStudio/br-consignado-gw" = {
        role_name = "consignado-github-oidc-s3-upload"
        services  = ["br-consignado-gw"]
      }
    }
  }

  expect_failures = [var.github_repositories]
}

run "empty_refs_refused" {
  command = plan

  # A role no token can assume: it applies, and every upload is denied.
  variables {
    github_repositories = {
      "LerianStudio/lender" = {
        role_name = "lender-github-oidc-s3-upload"
        services  = ["lender"]
        refs      = []
      }
    }
  }

  expect_failures = [var.github_repositories]
}

run "duplicate_ref_refused" {
  command = plan

  variables {
    github_repositories = {
      "LerianStudio/lender" = {
        role_name = "lender-github-oidc-s3-upload"
        services  = ["lender"]
        refs      = ["refs/heads/main", "refs/heads/main"]
      }
    }
  }

  expect_failures = [var.github_repositories]
}

run "every_branch_refused" {
  command = plan

  # Every branch, including one pushed by anyone with write access and never
  # reviewed.
  variables {
    github_repositories = {
      "LerianStudio/lender" = {
        role_name = "lender-github-oidc-s3-upload"
        services  = ["lender"]
        refs      = ["refs/heads/*"]
      }
    }
  }

  expect_failures = [var.github_repositories]
}

run "branch_prefix_glob_refused" {
  command = plan

  variables {
    github_repositories = {
      "LerianStudio/lender" = {
        role_name = "lender-github-oidc-s3-upload"
        services  = ["lender"]
        refs      = ["refs/heads/feat/*"]
      }
    }
  }

  expect_failures = [var.github_repositories]
}

run "pull_request_ref_refused" {
  command = plan

  # The merge ref of a pull request runs code nobody merged yet.
  variables {
    github_repositories = {
      "LerianStudio/lender" = {
        role_name = "lender-github-oidc-s3-upload"
        services  = ["lender"]
        refs      = ["refs/pull/1/merge"]
      }
    }
  }

  expect_failures = [var.github_repositories]
}

run "branch_without_name_refused" {
  command = plan

  variables {
    github_repositories = {
      "LerianStudio/lender" = {
        role_name = "lender-github-oidc-s3-upload"
        services  = ["lender"]
        refs      = ["refs/heads/"]
      }
    }
  }

  expect_failures = [var.github_repositories]
}

run "bucket_arn_instead_of_name_refused" {
  command = plan

  # The variable is used to BUILD an ARN. An ARN pasted here produces
  # arn:aws:s3:::arn:aws:s3:::bucket/... — a resource that matches nothing, so
  # the apply succeeds and every upload is denied.
  variables {
    migrations_bucket_name = "arn:aws:s3:::tenant-manager-prd-migrations-862902859103"
  }

  expect_failures = [var.migrations_bucket_name]
}

run "bucket_name_with_adjacent_periods_refused" {
  command = plan

  variables {
    migrations_bucket_name = "tenant-manager..migrations"
  }

  expect_failures = [var.migrations_bucket_name]
}

run "bucket_name_formatted_as_ipv4_refused" {
  command = plan

  variables {
    migrations_bucket_name = "192.168.5.4"
  }

  expect_failures = [var.migrations_bucket_name]
}
