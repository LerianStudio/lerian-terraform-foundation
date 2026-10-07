# products/lender

AWS datastores, custody bucket and vault identity for **lender** (ex-underwriter; the lending
product): products, origination, servicing, accounting, portfolio, audit.

```
examples/aws/products/lender/
├── postgres/     -> _modules/postgres-rds          lender-{env}-postgres
├── s3/           -> _modules/s3-bucket             lender-{env}-issuance-custody-{account_id}
├── secrets/      -> _modules/irsa-secretsmanager   lender-{env}-secrets-irsa
└── valkey/       -> _modules/valkey-elasticache    lender-{env}-valkey
```

`secrets/` is the IRSA role the lender reads its per-tenant M2M credentials with
(`tenants/{ENV_NAME}/*/lender/m2m/`), with the Dataprev custody path denied. Unlike the two datastores, its
`helm_values` is verified against helm-internal `charts/lender`; see
[`secrets/README.md`](secrets/README.md).

`s3/` is the lender's custody bucket for CCB instruments, cessão dossiers and
assignment terms. It creates no role: `secrets/` attaches its policy to the one
lender role. See [`s3/README.md`](s3/README.md).

See [`../midaz/README.md`](../midaz/README.md) for everything identical across
products: the `lerian-` / `shared-` prefix split, `module.network`, the absence
of private DNS, and why `endpoint` is always the raw AWS host.

---

## ⚠ The datastore roots' `helm_values` are not mapped yet

The lender chart is `oci://ghcr.io/lerianstudio/helm-internal/lender-helm`
(source: helm-internal `charts/lender`). `secrets/` is mapped against it.
`postgres/` and `valkey/` are not: both `outputs.tf` files export
`helm_values = {}`, and the database name defaults to `"lender"` as an
infrastructure choice nobody has confirmed. This is deliberate, and it is the
safer failure:

> A wrong env var name does not fail the plan, does not fail the Helm render,
> and does not fail the pod start. It produces a service quietly talking to the
> chart's in-cluster default while the RDS instance sits idle — surfacing in
> production, as data written to the wrong place.

An incomplete-and-honest `helm_values` is useful. An invented one is a
production incident with a plausible-looking commit behind it.

### Why guessing Redis names is especially unsafe here

Among the four Lerian charts that *are* readable, the same variable name behaves
four different ways:

| Chart | shape |
|---|---|
| midaz | `REDIS_HOST` carries `"host:port"`; `REDIS_PORT` was deleted in chart 3.0 |
| br-consignado-gw | `REDIS_HOST` carries `"host:port"`; it is the only Redis key at all |
| plugin-access-manager | `REDIS_HOST` is a **bare** host and the template appends `REDIS_PORT` — passing `host:port` yields `host:port:port` |
| tracer | no plain `REDIS_*`; only `MULTI_TENANT_REDIS_HOST` (bare) plus `MULTI_TENANT_REDIS_PORT` |

There is no majority and no Lerian-wide convention. The postgres side is no
better: `DB_ONBOARDING_*`, `DB_HOST`, and `POSTGRES_HOST` are all in production
use across the four.

`products/lender/valkey` therefore publishes **both** candidate shapes as
first-class outputs — `endpoint` and `port` split, plus `redis_host_port`
joined — so that whoever reads the chart can wire the release without coming
back to Terraform.

### To close this

1. Read `lender-helm`'s `values.yaml` and the template that renders its
   ConfigMap.
2. For Redis, check specifically whether the port is a separate key, embedded in
   the host, or appended by the template.
3. Fill `helm_values` in both `outputs.tf`, replacing the `⚠` block with a
   `Verified against chart <name> <version>, <file:line>` note like the tracer
   and br-consignado-gw roots carry.
4. Confirm `database_name` with the owning team and update the tfvars.

Until then: **do not run these stacks in production.** The infrastructure is
correct; the handoff is not mapped.

## What IS verified

Everything that does not depend on the chart:

- naming, tagging and the anti-collision contract (`lender-{env}-postgres`,
  `lender-{env}-valkey`, and the matching Secrets Manager paths);
- VPC / subnet / EKS-node-security-group resolution through `module.network`;
- the ingress model, the `dedicated` / `shared` switch, the seven uniform
  outputs;
- sizing per environment, copied from `products/midaz` without invention;
- `terraform validate`, `tflint` and `trivy config` clean.

## Helm handoff (what to map by hand)

Both roots publish everything a consumer needs as individual outputs:

```bash
cd examples/aws/products/lender/postgres
terraform output -raw endpoint
terraform output -raw port
terraform output -raw database_name
terraform output -raw username
terraform output -raw secret_name

cd ../valkey
terraform output -raw endpoint          # bare host
terraform output -raw port
terraform output -raw redis_host_port   # "host:port", for a chart that wants it joined
terraform output -raw secret_name
```

No password is ever an output. `secret_name` is what an External Secrets
Operator `ExternalSecret` references.

## Security posture

`auth_token_enabled = false` and `transit_encryption_mode = "preferred"` in all
three environments, **including production**, because neither the
application's AUTH support nor its TLS trust store has been verified against the
chart. Flipping either switch blind is how a production cache goes dark.

The token *is* generated and stored at `lender-{env}-valkey/auth-token`
regardless, so enabling it later is a tfvars change, not a rebuild.

## Deploy order

```
1. examples/aws/bootstrap
2. examples/aws/infra-base/vpc            -> lerian-{env}-vpc
3. examples/aws/infra-base/eks            -> lerian-{env}-eks
4. examples/aws/products/shared-resources/*   (OPTIONAL, only for mode = "shared")
5. products/lender/{postgres,valkey,s3}   <- in any order, in parallel
6. products/lender/secrets                <- after s3: it attaches the s3 policy
7. helm upgrade --install lender oci://ghcr.io/lerianstudio/helm-internal/lender-helm
                                          <- datastore values mapped by hand, see above
```

## Running a stack

```bash
cd examples/aws/products/lender/postgres

terraform init \
  -backend-config=../../../backend/dev.hcl \
  -backend-config="key=aws/products/lender/postgres/terraform.tfstate"

cp envs/dev.tfvars-example envs/dev.tfvars   # then edit
terraform plan  -var-file=envs/dev.tfvars -out=tfplan
terraform apply tfplan
```

| Stack | State key |
|---|---|
| postgres | `aws/products/lender/postgres/terraform.tfstate` |
| s3 | `aws/products/lender/s3/terraform.tfstate` |
| secrets | `aws/products/lender/secrets/terraform.tfstate` |
| valkey | `aws/products/lender/valkey/terraform.tfstate` |

## What gets created

`mode = "dedicated"`, `environment = "dev"`:

| Stack | AWS resource | Secrets Manager | ~USD/month |
|---|---|---|---|
| postgres | `lender-dev-postgres` (RDS `db.t4g.micro`, 20 GB) | `lender-dev-postgres/password` | 15 |
| valkey | `lender-dev-valkey` (ElastiCache `cache.t4g.micro`, 1 node) | `lender-dev-valkey/auth-token` | 12 |
| s3 | `lender-dev-issuance-custody-{account_id}` (bucket + IAM policy) | — | 0 + storage |
| secrets | `lender-dev-secrets-irsa` (IAM role + policy) | — | 0 |
| **total** | | | **~27** |

Estimates; price them against your own AWS Pricing Calculator.
