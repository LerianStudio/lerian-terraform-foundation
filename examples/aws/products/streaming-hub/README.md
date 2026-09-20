# `streaming-hub`

The event delivery edge: it consumes CloudEvents off Kafka and fans them out per
tenant to webhooks, SQS, RabbitMQ and EventBridge.

| Root | What it provisions | Mode |
|---|---|---|
| `postgres` | The hub's only mandatory datastore | `dedicated` |
| `valkey` | Rate-limiter counters, one per environment | `dedicated` |
| `msk` | Resolves the Kafka the producers publish to | **`shared`** |
| `secrets` | IRSA for the tenant roster listing | n/a |

## What it does NOT need, measured

- **No DocumentDB, no S3, no KMS.** SQS, EventBridge and RabbitMQ appear in the
  dependency list as *customer-owned delivery sinks*, reached with credentials that
  arrive per subscription from the decrypted database config. Provision none of them.

## Four things that bite

**`valkey` must be `dedicated`, and nothing checks that it is.** The 2.x line counts
per-tenant rate limits in it, every role mounts `/v1` so every pod needs it, and the
boot refuses a blank `STREAMING_HUB_REDIS_ADDRESS`. It refuses nothing else: pointing
it at `MULTI_TENANT_REDIS_HOST` — the tenant-manager's lifecycle bus, not a counter
store — boots clean and silently shares a keyspace. The warning against it is prose
inside an error message, not a gate. The 1.x claim that the hub needs no Redis is no
longer true.

**`msk` must be `shared`.** The hub subscribes by regex — `^lerian\.streaming\.<app>$`
— so it can only see what a producer wrote to the *same cluster*. A dedicated broker
gives a healthy pod that consumes nothing, and an empty regex match is not a failure
condition anywhere in Kafka.

**The KEK is not a Secrets Manager dependency, despite appearances.**
`STREAMING_HUB_KEK_SOURCE` accepts the literal `secretsmanager`, and both that value
and `env` resolve through the same environment-variable source with no AWS SDK
involved. What the KEK needs is an ExternalSecret projecting it as an env var. An
empty KEK makes the hub *refuse to sign* webhooks rather than degrade.

**`ListSecrets` is load-bearing and unscopeable.** In multi-tenant mode the roster
IS the vault listing, an empty listing refuses the boot, and AWS does not evaluate
`ListSecrets` against a resource. Grant it to every hub pod, not only ingest.

## Topics

Nothing here creates them. `auto.create.topics.enable` is false and the set is
whatever `ce-source` values the producers use. See `../lerian-platform/README.md`
for the list this estate needs and where the `rpk` Job lives.
