# `products/lender/secrets`

IRSA for the lender's vault reads: role `lender-{env}-secrets-irsa`, bound to the
lender ServiceAccount.

The lender reads its per-tenant M2M credential for each service it calls (midaz,
consignado-gateway, matcher) at
`tenants/{ENV_NAME}/{tenantOrgID}/lender/m2m/{target}/credentials`. Once the
Midaz relay is configured that read is a boot requirement: an unreadable
credential stops the process.

## What the role may touch

| | |
|---|---|
| **Allow** `GetSecretValue` | `tenants/{app_env_name}/*/lender/m2m/*` and `installation/{app_env_name}/lender/*` |
| **Deny** `secretsmanager:*` | `tenants/*/*/*/external/*`: the Dataprev custody credentials, which only br-consignado-gw may read |

Both allow prefixes are **derived from `app_env_name`**, so the vault scope and the
`ENV_NAME` the pod boots with cannot disagree. The Deny is a literal in `main.tf`,
not a variable, so no tfvars can drop it. No `ListSecrets`, no writes: tenant
credentials are written by tenant-manager.

## Helm handoff

`helm_values` emits dotted paths of helm-internal `charts/lender`:

- `lender.serviceAccount.annotations.eks\.amazonaws\.com/role-arn`: the role.
- `lender.configmap.ENV_NAME`: must equal `app_env_name`.
- `lender.configmap.AWS_REGION`: the chart defaults to `us-east-1`; a lender
  reading the wrong region reports its credential missing.

`service_account` defaults to `lender:lender`, what the chart renders with no
override. A release that renames the namespace or the ServiceAccount needs the
same value here.
