# AmazonMQ Upgrade Guide: Single Instance to Cluster Mode

## CRITICAL WARNING: Resource Recreation

**Migrating from `SINGLE_INSTANCE` to `CLUSTER_MULTI_AZ` causes RESOURCE RECREATION.**

This means:
- The existing broker will be DESTROYED
- All queues will be DELETED
- All pending messages will be LOST
- Application credentials need to be reconfigured
- A new cluster broker will be created with a new endpoint

### Why This Happens

AWS AmazonMQ does not support in-place upgrade from single instance to cluster mode. Terraform will detect this as a resource replacement because:

1. The `deployment_mode` change requires a new broker
2. The broker name changes (e.g., `midaz-mq-single` to `midaz-mq-cluster`)
3. The `subnet_ids` configuration changes (1 subnet to 2-3 subnets)

---

## Recommended Upgrade Procedure

**Our recommendation:** Create a NEW cluster broker alongside the existing single instance broker, then switch traffic. Do NOT apply terraform changes directly over the existing broker.

### Prerequisites

Before starting the upgrade:

- [ ] Ensure you have at least 2-3 private subnets in DIFFERENT availability zones
- [ ] Verify instance type is `mq.m5.large` or larger (NOT `mq.t3.*`)
- [ ] Plan for brief application restart during traffic switch
- [ ] Have application deployment access ready

### Step 1: Create New Cluster Broker (Keep Single Instance Running)

**Purpose:** Create the new cluster broker without destroying the existing single instance.

Copy the AmazonMQ terraform to a new folder (e.g., `amazonmq-cluster/`) and configure for cluster mode:

```hcl
# New cluster configuration
name               = "midaz-mq"           # Will become "midaz-mq-cluster"
deployment_mode    = "CLUSTER_MULTI_AZ"
host_instance_type = "mq.m5.large"
```

Apply the new terraform:

```bash
cd amazonmq-cluster/
terraform init
terraform apply -var-file=cluster.tfvars
```

**Expected duration:** ~10 minutes for cluster creation.

At this point you will have BOTH brokers running:
- `midaz-mq-single` (existing, still serving traffic)
- `midaz-mq-cluster` (new, ready to receive traffic)

### Step 2: Setup Queues and Credentials on New Cluster

**Purpose:** Prepare the new cluster with the same queue configuration.

```bash
# Get new cluster endpoint and credentials
terraform output broker_primary_endpoint
aws secretsmanager get-secret-value \
  --secret-id "midaz-mq-cluster/amazonmq-password" \
  --query SecretString --output text

# Create queues on new cluster using RabbitMQ Management API
curl -u $MQ_USER:$MQ_PASSWORD -X PUT \
  https://<new-cluster-endpoint>:15671/api/queues/%2F/your-queue-name \
  -H "content-type: application/json" \
  -d '{"durable": true}'
```

### Step 3: Turn Off Traffic to Midaz Application

**Purpose:** Prevent new messages from being added to queues during switch.

Disable incoming traffic to your Midaz application. The method depends on your infrastructure setup (ingress controller, load balancer, API gateway, etc.).

### Step 4: Drain Existing Queues

**Purpose:** Process all pending messages to prevent data loss.

```bash
# Monitor queue depths until empty
curl -u $MQ_USER:$MQ_PASSWORD \
  https://<old-broker-endpoint>:15671/api/queues | jq '.[] | {name, messages}'
```

**Verification:** All queues should show `messages: 0` before proceeding.

### Step 5: Switch Application to New Cluster

**Purpose:** Point the application to the new cluster broker.

Update your application's Helm values with the new cluster endpoint and credentials, then redeploy.

### Step 6: Re-enable Traffic

Re-enable incoming traffic to your Midaz application using the same method you used to disable it.

### Step 7: Verify Operation

```bash
# Check application logs for successful connections
kubectl logs -l app=midaz-app | grep -i rabbitmq

# Verify messages are being processed on new cluster
curl -u $MQ_USER:$MQ_PASSWORD \
  https://<new-cluster-endpoint>:15671/api/queues | jq '.[] | {name, messages}'
```

### Step 8: Destroy Old Single Instance Broker (After Stabilization)

**Purpose:** Clean up the old broker after confirming the new cluster is stable.

**Wait at least a few hours** before destroying the old broker, in case you need to rollback.

```bash
cd amazonmq-single/
terraform destroy -var-file=single.tfvars
```

---

## Alternative: In-Place Upgrade (NOT RECOMMENDED)

**WARNING: We strongly advise against applying this change directly over an existing AmazonMQ broker in production environments.**

If you choose to upgrade in-place:
- The existing broker will be **DESTROYED**
- All queues, messages, and configurations will be **PERMANENTLY LOST**
- There is **NO ROLLBACK** option
- Downtime is approximately **10-15 minutes**

**Use this method ONLY for non-production environments (dev, test, staging).**

**DISCLAIMER:** If you proceed with an in-place upgrade and lose RabbitMQ objects (queues, messages, bindings, etc.), this is entirely at your own risk. We are not responsible for any data loss resulting from this approach.

### Step 1: Update Terraform Variables

Update your `.tfvars` file with the following changes:

#### Terraform Variables Reference

| Variable | Single Instance | Cluster Mode | Change Required | Why |
|----------|-----------------|--------------|-----------------|-----|
| `deployment_mode` | `SINGLE_INSTANCE` | `CLUSTER_MULTI_AZ` | **YES** | Enables 3-node HA cluster with automatic failover |
| `host_instance_type` | `mq.t3.micro` or `mq.m5.large` | `mq.m5.large` or larger | **YES** if using mq.t3.* | `mq.t3.micro` does not support cluster deployment (AWS limitation) |
| `engine_type` | `RabbitMQ` or `ActiveMQ` | `RabbitMQ` only | **YES** if using ActiveMQ | ActiveMQ does not support `CLUSTER_MULTI_AZ` mode |
| `engine_version` | Any supported | Any supported | No | Same RabbitMQ versions supported |
| `name` | e.g., `midaz-mq` | e.g., `midaz-mq` | No | Suffix `-single` or `-cluster` auto-added by Terraform |
| `vpc_name` | VPC with 1+ private subnet | VPC with 2-3 private subnets in different AZs | **YES** if VPC lacks multi-AZ subnets | Cluster requires subnets in different AZs for HA |
| `environment` | Any | Any | No | Tag only, no functional impact |
| `mq_admin_user` | Any | Any | No | Same username works, but new password generated |
| `publicly_accessible` | `true` or `false` | `true` or `false` | No | Same behavior in both modes |
| `auto_minor_version_upgrade` | `true` or `false` | `true` or `false` | No | Recommended `true` for security patches |

#### EBS Storage Differences (AWS-managed, not configurable)

| Instance Type | Single Instance Disk | Cluster Mode Disk (per node) |
|---------------|---------------------|------------------------------|
| `mq.t3.micro` | 20 GB | Not supported |
| `mq.m5.large` | 200 GB | 200 GB |
| `mq.m5.xlarge` | 200 GB | 200 GB |
| `mq.m7g.large` | 200 GB | 15 GB |
| `mq.m7g.xlarge` | 200 GB | 25 GB |

**Note:** In cluster mode, data is replicated across 3 nodes, so effective storage is shared. AWS manages EBS volumes automatically - you cannot configure disk size via Terraform.

#### Example .tfvars Changes

```hcl
# Before (Single Instance)
deployment_mode    = "SINGLE_INSTANCE"
host_instance_type = "mq.t3.micro"

# After (Cluster Mode)
deployment_mode    = "CLUSTER_MULTI_AZ"
host_instance_type = "mq.m5.large"  # REQUIRED: mq.t3.* not supported
```

#### Key Constraints for Cluster Mode

1. **deployment_mode**: Must be `CLUSTER_MULTI_AZ`
2. **host_instance_type**: Must be `mq.m5.large` or larger (mq.t3.* NOT supported)
3. **engine_type**: Must be `RabbitMQ` (ActiveMQ does not support cluster mode)
4. **VPC**: Must have 2-3 private subnets in DIFFERENT availability zones

### Step 4: Review Terraform Plan

```bash
cd examples/aws/amazonmq
terraform plan -var-file=midaz.tfvars

# EXPECTED OUTPUT:
# aws_mq_broker.main will be destroyed
# aws_mq_broker.main will be created
# aws_secretsmanager_secret.mq_password will be destroyed
# aws_secretsmanager_secret.mq_password will be created
```

**Verify the plan shows resource replacement, not just update.**

### Step 5: Apply Terraform

```bash
terraform apply -var-file=midaz.tfvars
```

**Expected duration breakdown (based on real-world testing):**

| Phase | Duration |
|-------|----------|
| Destroy single instance broker | ~10 seconds |
| Security group cleanup | ~1 minute |
| Create cluster broker | **~10 minutes** |
| **Total upgrade time** | **~11-12 minutes** |

**Note:** During this time, your application will have NO message broker connectivity. Plan for approximately **10-15 minutes of downtime**.

**IMPORTANT: The broker endpoint URL will change!** The broker ID is part of the endpoint URL, so when the broker is recreated, you get a completely new endpoint:

```
# Example endpoint change:
Before: amqps://b-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx.mq.us-east-2.on.aws:5671
After:  amqps://b-yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy.mq.us-east-2.on.aws:5671
```

You **must** update your application configuration with the new endpoint after the upgrade completes.

### Step 6: Retrieve New Credentials and Endpoint

```bash
# Get new broker endpoint
terraform output broker_primary_endpoint

# Get new password from Secrets Manager
aws secretsmanager get-secret-value \
  --secret-id "midaz-mq-cluster/amazonmq-password" \
  --query SecretString --output text
```

### Step 7: Setup Queues on New Broker

Recreate your queues on the new cluster:

```bash
# Using RabbitMQ Management API
curl -u $MQ_USER:$MQ_PASSWORD -X PUT \
  https://<new-broker-endpoint>:15671/api/queues/%2F/your-queue-name \
  -H "content-type: application/json" \
  -d '{"durable": true}'
```

### Step 8: Update Application Configuration

Update your application's Helm values with the new cluster endpoint (broker host), then redeploy.

Your application must support **automatic reconnection** for cluster mode. During maintenance or failover, connections will be severed and need to be re-established.

### Step 9: Re-enable Traffic

```bash
# Scale application back up
kubectl scale deployment midaz-app --replicas=3

# Or re-enable load balancer/ingress
```

### Step 10: Verify Operation

```bash
# Check application logs for successful connections
kubectl logs -l app=midaz-app | grep -i rabbitmq

# Verify messages are being processed
curl -u $MQ_USER:$MQ_PASSWORD \
  https://<new-broker-endpoint>:15671/api/queues | jq '.[] | {name, messages}'
```

---

## Rollback Considerations

### If Upgrade Fails

1. **Do NOT revert Terraform immediately** - this will destroy the new cluster
2. Debug the issue first
3. If you must rollback:
   ```bash
   # Revert tfvars to single instance
   deployment_mode    = "SINGLE_INSTANCE"
   host_instance_type = "mq.t3.micro"
   
   # Apply - WARNING: This destroys the cluster and creates a new single instance
   terraform apply -var-file=midaz.tfvars
   ```

### If Application Fails to Connect

1. Verify security group allows traffic from application
2. Check the new endpoint URL is correct
3. Verify credentials are updated in application config
4. Check RabbitMQ logs in CloudWatch

---

## Testing Recommendations

### Before Production Upgrade

1. **Test in staging environment first**
   - Create a staging cluster with same configuration
   - Verify application connects successfully
   - Run load tests to verify performance

2. **Verify subnet configuration**
   ```bash
   # List private subnets and their AZs
   aws ec2 describe-subnets \
     --filters "Name=tag:Type,Values=private" \
     --query 'Subnets[*].[SubnetId,AvailabilityZone]' \
     --output table
   ```

3. **Test failover behavior**
   - Connect to cluster
   - Simulate node failure
   - Verify automatic failover works

### Acceptance Criteria

- [ ] Application connects to new cluster endpoint
- [ ] Messages are produced and consumed successfully
- [ ] No message loss detected
- [ ] Monitoring/alerting is reconfigured for new broker
- [ ] Terraform state shows healthy cluster resources

---

## Quick Reference

| Aspect | SINGLE_INSTANCE | CLUSTER_MULTI_AZ |
|--------|-----------------|------------------|
| Subnets Required | 1 | 2-3 (different AZs) |
| Instance Types | Any | mq.m5.large+ (NOT mq.t3.*) |
| Engine Types | ActiveMQ, RabbitMQ | RabbitMQ ONLY |
| High Availability | No | Yes |
| Automatic Failover | No | Yes |
| Typical Cost | $ | $$$ |

---

## Support

If you encounter issues during migration:

1. Check AWS CloudWatch logs for the broker
2. Review Terraform state: `terraform state show aws_mq_broker.main`
3. Contact infrastructure team with:
   - Terraform plan output
   - Application error logs
   - Broker CloudWatch logs
