################################################################################
# Outputs
#
# The seven uniform contract names (mode, endpoint, port, security_group_id,
# secret_arn, secret_name, identifier) are passed straight through from the
# module, unchanged, so every products/*/* root answers `terraform output` the
# same way regardless of which datastore it wraps.
#
# There is no dns_name output and no private zone: every AWS datastore presents
# a certificate for its own service domain, so a CNAME in front of it breaks TLS
# hostname verification. `endpoint` is the raw AWS host in both modes.
#
# The module is NOT under count here — this root stack wraps exactly one
# datastore — so a plain module.valkey.x reference is safe.
################################################################################

locals {
  ################################################################################
  # STREAMING_HUB_REDIS_ADDRESS is "host:port", not a host.
  #
  # The hub defines no separate port variable — the four keys it reads are
  # STREAMING_HUB_REDIS_{ADDRESS,PASSWORD,TLS,CA_CERT} — and the chart's own
  # example carries the port inside the address
  # (charts/streaming-hub/values-template.yaml:39). A bare hostname here
  # produces a client that dials port 0.
  #
  # This is the OPPOSITE of plugin-access-manager, whose template appends the
  # port itself, so a "host:port" value there renders as host:port:port. Read
  # the consuming template before copying this block between products.
  ################################################################################
  redis_address = "${module.valkey.endpoint}:${module.valkey.port}"
}

################################################################################
# Cross-stack context (assert the derived strings without opening the tfvars)
################################################################################

output "vpc_name" {
  description = "tag:Name of the VPC the replication group was placed in, as derived or overridden. Should equal the vpc_name output of infra-base/vpc."
  value       = module.network.vpc_name
}

output "eks_cluster_name" {
  description = "EKS cluster whose node security group was looked up. Note the \"lerian\" prefix: the cluster belongs to infra-base, not to streaming-hub."
  value       = module.network.eks_cluster_name
}

output "ingress_security_group_ids" {
  description = "Security groups authorised on the replication group. Empty before infra-base/eks exists unless allowed_security_group_ids was passed explicitly."
  value       = module.network.ingress_security_group_ids
}

output "ingress_cidr_blocks" {
  description = "CIDR blocks authorised on the replication group. Holds the Type=private subnet CIDRs while allow_private_subnet_cidr_ingress is true."
  value       = module.network.ingress_cidr_blocks
}

################################################################################
# Uniform datastore contract
################################################################################

output "mode" {
  description = "Provisioning mode this stack ran in: dedicated or shared."
  value       = module.valkey.mode
}

output "endpoint" {
  description = "Raw AWS primary endpoint of the replication group — the host HALF of STREAMING_HUB_REDIS_ADDRESS. The hub wants host and port in one string, so use helm_values rather than this output directly. In shared mode this is the primary endpoint of shared-{env}-valkey, resolved by name."
  value       = module.valkey.endpoint
}

output "port" {
  description = "Valkey port. The hub has no separate port variable — this value is folded into STREAMING_HUB_REDIS_ADDRESS by helm_values."
  value       = module.valkey.port
}

output "security_group_id" {
  description = "Security group protecting the replication group. Null in shared mode — ingress on the shared group is owned by products/shared-resources/valkey."
  value       = module.valkey.security_group_id
}

output "secret_arn" {
  description = "ARN of the Secrets Manager secret holding the auth token: streaming-hub-{env}-valkey/auth-token in dedicated mode, shared-{env}-valkey/auth-token in shared mode."
  value       = module.valkey.secret_arn
}

output "secret_name" {
  description = "Name of the Secrets Manager secret holding the auth token. The token exists whether or not ElastiCache enforces it. This is the entry the release must project as STREAMING_HUB_REDIS_PASSWORD before auth_token_enabled can be turned on — the value is key material and is deliberately NOT an output of this stack."
  value       = module.valkey.secret_name
}

output "identifier" {
  description = "ElastiCache replication group id: streaming-hub-{environment}-valkey in dedicated mode, the resolved shared-{env}-valkey in shared mode."
  value       = module.valkey.identifier
}

################################################################################
# Valkey specifics
################################################################################

output "reader_endpoint" {
  description = "Reader endpoint of the replication group. Empty when the group has a single cache cluster. The hub has no reader variable — the rate limiters read and write the primary — so nothing consumes this today."
  value       = module.valkey.reader_endpoint
}

output "engine_version_actual" {
  description = "Running version of the cache engine. Null in shared mode."
  value       = module.valkey.engine_version_actual
}

output "auth_token_enabled" {
  description = "Whether ElastiCache is ENFORCING the auth token stored in secret_name. Safe to turn on only once the release projects that secret as STREAMING_HUB_REDIS_PASSWORD; the hub reads it, so nothing in the chart blocks this."
  value       = module.valkey.auth_token_enabled
}

output "transit_encryption_enabled" {
  description = "Whether in-transit encryption is enabled on the replication group. Available is not the same as REQUIRED — see transit_encryption_mode, which decides whether the listener still accepts a plaintext client. It is also what helm_values derives STREAMING_HUB_REDIS_TLS from."
  value       = module.valkey.transit_encryption_enabled
}

output "subnet_group_name" {
  description = "Name of the cache subnet group. Null in shared mode."
  value       = module.valkey.subnet_group_name
}

################################################################################
# Helm handoff
#
# The hub reads exactly four keys for this cache, and they are the
# STREAMING_HUB_REDIS_* block — NOT the MULTI_TENANT_REDIS_* one. The two only
# look alike: MULTI_TENANT_REDIS_* addresses the platform tenant-manager's
# lifecycle bus, and the boot refuses this stack's cache being pointed there.
#
#   STREAMING_HUB_REDIS_ADDRESS   "host:port". Required on every role, because
#     every role mounts the /v1 control plane. A blank one fails the boot.
#   STREAMING_HUB_REDIS_TLS       defaults to TRUE in the hub, and a hardened
#     environment (staging, production) refuses to boot with it false.
#   STREAMING_HUB_REDIS_PASSWORD  a Secret, never a ConfigMap key. Emitted
#     when set, legitimately absent while auth_token_enabled is false.
#   STREAMING_HUB_REDIS_CA_CERT   base64 PEM. Left empty on purpose: ElastiCache
#     in-transit encryption presents a publicly trusted certificate, which the
#     Go system pool already validates.
#
# TWO KEYS EMITTED HERE, and the two omissions are deliberate:
#   PASSWORD — key material. It stays in Secrets Manager and reaches the pod as
#     an ExternalSecret; `secret_name` above names the entry. A terraform output
#     is world-readable to anyone holding the state file.
#   CA_CERT  — empty is the correct value, and emitting "" would read as an
#     unfinished wiring rather than a measured decision.
################################################################################

output "helm_values" {
  description = "streaming-hub env vars this datastore fills in. STREAMING_HUB_REDIS_ADDRESS carries \"host:port\" — the hub has no separate port variable. STREAMING_HUB_REDIS_TLS follows transit_encryption_enabled; the hub defaults it to true and a hardened environment refuses false. The password is NOT here on purpose: it is key material, projected from secret_name by an ExternalSecret."
  value = {
    STREAMING_HUB_REDIS_ADDRESS = local.redis_address
    STREAMING_HUB_REDIS_TLS     = tostring(module.valkey.transit_encryption_enabled)
  }
}
