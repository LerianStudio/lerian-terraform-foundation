################################################################################
# What the lender's role reaches, read off the patterns the policy is built from
#
# The allow is DERIVED from app_env_name, so a wrong segment applies cleanly and
# surfaces as a lender that will not boot over a "missing" credential. The other
# direction is worse and just as quiet: a prefix one segment too broad hands the
# lender every service's M2M credentials, or a tenant's Dataprev custody.
#
# The rendered policy document is a data source, so under mock_provider it is
# generated noise. The ARN patterns are plain locals of the module and are what
# the document is built from; the asserts below match concrete secret ARNs
# against them the way IAM does, with "*" spanning any run of characters,
# including "/".
#
# mock_provider: no AWS call, no credential, no state. The override_data blocks
# pin the partition, region and account the ARNs are built from.
################################################################################

mock_provider "aws" {}

override_data {
  target = module.secrets.data.aws_partition.current
  values = {
    partition = "aws"
  }
}

override_data {
  target = module.secrets.data.aws_region.current
  values = {
    region = "sa-east-1"
  }
}

override_data {
  target = module.secrets.data.aws_caller_identity.current
  values = {
    account_id = "123456789012"
  }
}

# The two policy documents, pinned to an empty JSON object: the mock otherwise
# generates a string that is not JSON, and the provider refuses it at plan.
override_data {
  target = module.secrets.data.aws_iam_policy_document.assume_role
  values = {
    json = "{}"
  }
}

override_data {
  target = module.secrets.data.aws_iam_policy_document.this
  values = {
    json = "{}"
  }
}

variables {
  region            = "sa-east-1"
  environment       = "prd"
  oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.sa-east-1.amazonaws.com/id/0123456789ABCDEF0123456789ABCDEF"
}

run "lender_paths_only_and_never_custody" {
  command = plan

  assert {
    condition     = output.iam_role_name == "lender-prd-secrets-irsa"
    error_message = "The role is not named lender-prd-secrets-irsa, the name the estate's chart values discover it by."
  }

  # Every target the lender calls, for any tenant, is reachable.
  assert {
    condition = alltrue([
      for target in ["midaz", "consignado-gateway", "matcher"] : anytrue([
        for pattern in output.secret_arn_patterns :
        can(regex("^${replace(pattern, "*", ".*")}$", "arn:aws:secretsmanager:sa-east-1:123456789012:secret:tenants/production/org-1/lender/m2m/${target}/credentials-AbCdEf"))
      ])
    ])
    error_message = "A lender M2M credential under tenants/production/{tenant}/lender/m2m/{target}/credentials is not covered by the allow. The lender refuses to boot when the Midaz relay's credential is unreadable."
  }

  # Nothing that is not the lender's: another service's M2M credential, another
  # service's installation secret, another environment, and the custody path.
  assert {
    condition = alltrue(flatten([
      for secret in [
        "tenants/production/org-1/br-consignado-gw/external/dataprev/credentials/versions/v1-AbCdEf",
        "tenants/production/org-1/streaming-hub/m2m/midaz/credentials-AbCdEf",
        "tenants/production/org-1/matcher/m2m/midaz/credentials-AbCdEf",
        "installation/production/streaming-hub/kek-AbCdEf",
        "tenants/staging/org-1/lender/m2m/midaz/credentials-AbCdEf",
        ] : [
        for pattern in output.secret_arn_patterns :
        !can(regex("^${replace(pattern, "*", ".*")}$", "arn:aws:secretsmanager:sa-east-1:123456789012:secret:${secret}"))
      ]
    ]))
    error_message = "The allow reaches a secret that is not the lender's: a Dataprev custody credential, another service's M2M credential or installation secret, or another environment."
  }

  # The custody Deny, wired with the four-segment shape that matches
  # tenants/{env}/{org}/{app}/external/ and not a module named "external".
  assert {
    condition     = module.secrets.denied_arn_patterns == ["arn:aws:secretsmanager:sa-east-1:123456789012:secret:tenants/*/*/*/external/*"]
    error_message = "The role does not carry exactly the custody Deny over tenants/*/*/*/external/*. Only br-consignado-gw may read a Dataprev custody credential."
  }
}
