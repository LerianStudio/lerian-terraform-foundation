# products/streaming-hub/valkey

The rate-limiter cache of the event delivery hub. Root stack over
[`_modules/valkey-elasticache`](../../../_modules/valkey-elasticache).

One root, one datastore, one state file. See [`../README.md`](../README.md) for
the product-level picture.

| | |
|---|---|
| Module | `../../../_modules/valkey-elasticache` |
| State key | `aws/products/streaming-hub/valkey/terraform.tfstate` |
| Creates | `streaming-hub-{env}-valkey` (ElastiCache replication group) |
| Secret | `streaming-hub-{env}-valkey/auth-token` |
| Hub reads | `STREAMING_HUB_REDIS_{ADDRESS,TLS,PASSWORD,CA_CERT}` |

## Run it

```bash
cd examples/aws/products/streaming-hub/valkey

terraform init \
  -backend-config=../../../backend/stg.hcl \
  -backend-config="key=aws/products/streaming-hub/valkey/terraform.tfstate"

cp envs/stg.tfvars-example envs/stg.tfvars   # then edit
terraform plan  -var-file=envs/stg.tfvars -out=tfplan
terraform apply tfplan
```

`../../../` is **three** levels up and lands on `examples/aws`. Verified with
`terraform init -backend=false`.

Prerequisites: `infra-base/vpc`. `infra-base/eks` is optional at apply time.

## Why the hub needs its own cache

The hub's per-tenant rate limiters count in this Valkey. Every role mounts the
`/v1` control plane, so **every pod** needs it, and the boot refuses a blank
`STREAMING_HUB_REDIS_ADDRESS` rather than serving with the limiters silently
disabled.

It must be the hub's **own** cache. `MULTI_TENANT_REDIS_*` is a different block
addressing the platform tenant-manager's lifecycle bus, and pointing this one at
it is refused at boot.

> The product README says the hub needs no Valkey. That was true of the 1.x
> line, where cron singleton-ing used `pg_try_advisory_xact_lock` and
> idempotency was a durable Postgres store. The 2.x line adds the rate limiters,
> and they need a counter store the replicas share.

## One address, and the port goes inside it

The hub defines no separate port variable. `STREAMING_HUB_REDIS_ADDRESS` carries
`host:port` in one string, as the chart's own example shows
(`charts/streaming-hub/values-template.yaml:39`):

```yaml
STREAMING_HUB_REDIS_ADDRESS: "valkey.dev-st.lerian.net:6379"
```

`helm_values` emits `"${endpoint}:${port}"`. A bare hostname produces a client
dialling port zero.

This is the **opposite** of `plugin-access-manager`, whose template appends the
port itself, so a `host:port` value renders as `host:port:port`. Read the
consuming template before copying a `helm_values` block between products.

## The two knobs that must move together

`transit_encryption_mode` and `auth_token_enabled` default loose —
`"preferred"` and `false` — so a **first** apply cannot lock out a release
nobody has wired yet. That is the only reason. Unlike the gateway, nothing in
this product blocks tightening them:

- `STREAMING_HUB_REDIS_TLS` **defaults to true** in the hub, and a hardened
  environment (staging, production) refuses to boot with it false.
- `STREAMING_HUB_REDIS_PASSWORD` is a key the chart emits when set, kept out of
  the ConfigMap because it is credential material.

`"preferred"` is worth stating plainly: it is not weaker TLS, it is **optional**
TLS — the listener still accepts a plaintext client. With no auth token on top,
any pod that can reach this security group reads and writes the rate-limiter
state of a multi-tenant service with no credential.

**The order is load-bearing.** Project `streaming-hub-{env}-valkey/auth-token`
as `STREAMING_HUB_REDIS_PASSWORD` in the release **first**, then flip the two
tfvars lines. Enforcing the token before the release can read it takes the
control plane down on every pod.

`envs/prd.tfvars-example` ships tightened; `envs/stg.tfvars-example` ships at
the first-apply posture with the upgrade written out.

`STREAMING_HUB_REDIS_CA_CERT` stays empty on purpose: ElastiCache in-transit
encryption presents a publicly trusted certificate, which the Go system pool
already validates.

## Ingress

Resolved by [`_modules/product-network`](../../../_modules/product-network) as
`module.network`, `enabled = var.mode == "dedicated"`: `Type=private` subnet
CIDRs plus the EKS node security group matched by
`tag:Name = "lerian-{env}-eks-node"` with the plural data source.
`check "eks_node_security_group_resolved"` lives in that module and warns while
the lookup is empty.

> `var.subnet_tag_type` (`"database"`) is the **placement** filter and goes to
> `valkey-elasticache` only. `product-network` keeps its own default
> (`"private"`), the **ingress** filter.

## Sizing

Both environment examples ship `cache.t4g.micro` with a single cache cluster.
The workload is three fixed-window counter tiers per tenant, not a cache of
anything expensive to recompute, so a node replacement costs a briefly more
permissive limiter and nothing else. Grow it from measurement.

A single cache cluster means no failover, no Multi-AZ and an empty
`reader_endpoint`. `multi_az_enabled` requires **both** `num_cache_clusters >= 2`
**and** `automatic_failover_enabled = true`; setting one without the others fails
the apply, not the plan.

## Outputs

Seven uniform contract names — `mode`, `endpoint`, `port`, `security_group_id`,
`secret_arn`, `secret_name`, `identifier` — plus `reader_endpoint`,
`engine_version_actual`, `auth_token_enabled`, `transit_encryption_enabled`,
`subnet_group_name`, the cross-stack context, and `helm_values`.

`helm_values` emits two keys, `STREAMING_HUB_REDIS_ADDRESS` and
`STREAMING_HUB_REDIS_TLS`. The password is **not** among them: it is key
material, it stays in Secrets Manager, and `secret_name` names the entry an
ExternalSecret projects. A terraform output is readable by anyone holding the
state file.

`endpoint` and `port` are published separately as well as combined, because a
raw endpoint is what any non-Helm consumer wants.

`endpoint` is the raw ElastiCache primary endpoint in both modes. There is no
`dns_name`: with transit encryption on, the certificate only covers
`*.{cluster}.{region}.cache.amazonaws.com`, so an alias in front of the primary
endpoint fails TLS hostname verification.

```bash
terraform output -json helm_values | jq
```

## Shared mode

`mode = "shared"` creates nothing and plans to zero resources. The module
resolves `shared-{env}-valkey` with
`data "aws_elasticache_replication_group"` and the secret
`shared-{env}-valkey/auth-token` with `data "aws_secretsmanager_secret"`, so
`endpoint`, `reader_endpoint` and `port` come from the resolved group.
`security_group_id` comes back `null`.

Not the mode this product uses: the hub's limiters share a keyspace with
whatever else counts in a shared group, and the eviction policy is then somebody
else's decision. The name is fully derived, so this root exposes no variable for
it; the module's own `shared_identifier` is the escape hatch.
