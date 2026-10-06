################################################################################
# What the lender's role reaches, read off its patterns and its rendered policy
#
# The allow is DERIVED from app_env_name, so a wrong segment applies cleanly and
# surfaces as a lender that will not boot over a "missing" credential. The other
# direction is worse and just as quiet: a prefix one segment too broad hands the
# lender every service's M2M credentials, or a tenant's Dataprev custody.
# Concrete secret ARNs are matched against the patterns the way IAM does, with
# "*" spanning any run of characters, including "/".
#
# A REAL provider with placeholder credentials, not mock_provider: the policy
# document is rendered locally by the provider, and a mock would generate it.
# Nothing here reaches AWS. A plan creates nothing, partition and region come
# from the provider configuration, and caller identity, the one data source
# that would call STS, is overridden.
################################################################################

provider "aws" {
  region                      = "sa-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

override_data {
  target = module.secrets.data.aws_caller_identity.current
  values = {
    account_id = "123456789012"
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

  # The rendered document, whole: one Allow of GetSecretValue alone on the
  # lender's prefix, and one Deny of every secretsmanager action on the custody
  # path, with the four-segment shape that matches tenants/{env}/{org}/{app}/
  # external/ and not a module named "external". No third statement: no
  # writes, no ListSecrets, no KMS.
  assert {
    condition = toset([
      for statement in jsondecode(module.secrets.policy_json).Statement :
      jsonencode([statement.Effect, statement.Action, statement.Resource])
      ]) == toset([
      jsonencode(["Allow", "secretsmanager:GetSecretValue", "arn:aws:secretsmanager:sa-east-1:123456789012:secret:tenants/production/*/lender/m2m/*"]),
      jsonencode(["Deny", "secretsmanager:*", "arn:aws:secretsmanager:sa-east-1:123456789012:secret:tenants/*/*/*/external/*"]),
    ]) && length(jsondecode(module.secrets.policy_json).Statement) == 2
    error_message = "The attached policy is not exactly an Allow of secretsmanager:GetSecretValue on tenants/production/*/lender/m2m/* plus a Deny of secretsmanager:* on tenants/*/*/*/external/*. Only br-consignado-gw may read a Dataprev custody credential, and the lender needs nothing beyond reading its own M2M credentials."
  }
}
