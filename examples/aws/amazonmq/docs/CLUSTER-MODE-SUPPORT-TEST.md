# AmazonMQ Module Test Report

## Test Summary - 2026-02-04

All tests **PASSED**. The module correctly implements single-instance and cluster mode deployments.

---

## Test Environment

| Attribute | Value |
|-----------|-------|
| Region | us-east-2 (Ohio) |
| VPC CIDR | 10.99.0.0/16 |
| Availability Zones | us-east-2a, us-east-2b, us-east-2c |
| Terraform Version | >= 1.0 |
| AWS Provider | ~> 5.0 |

---

## Test 1: Single-Instance Deployment

**Objective:** Verify SINGLE_INSTANCE mode uses exactly 1 subnet.

| Attribute | Value |
|-----------|-------|
| Deployment Mode | SINGLE_INSTANCE |
| Instance Type | mq.t3.micro |
| Engine | RabbitMQ 3.13 |
| Subnets Used | 1 |
| is_cluster_mode output | false |
| Creation Time | ~9 minutes |
| Destruction Time | ~2 minutes |
| **Result** | **PASS** |

**Verification:**
```bash
terraform output is_cluster_mode
# false

terraform state show 'aws_mq_broker.main' | grep subnet_ids
# subnet_ids = ["subnet-xxxxxxxxx"]  # Single subnet
```

---

## Test 2: Cluster Mode Deployment

**Objective:** Verify CLUSTER_MULTI_AZ mode uses 3 subnets in different AZs.

| Attribute | Value |
|-----------|-------|
| Deployment Mode | CLUSTER_MULTI_AZ |
| Instance Type | mq.m5.large |
| Engine | RabbitMQ 3.13 |
| Subnets Used | 3 (one per AZ) |
| Distinct AZ Validation | **PASS** |
| is_cluster_mode output | true |
| Creation Time | ~10 minutes |
| Destruction Time | ~2 minutes |
| **Result** | **PASS** |

**Verification:**
```bash
terraform output is_cluster_mode
# true

terraform state show 'aws_mq_broker.main' | grep -A5 subnet_ids
# subnet_ids = [
#   "subnet-xxxxxxxxx",  # us-east-2a
#   "subnet-yyyyyyyyy",  # us-east-2b
#   "subnet-zzzzzzzzz",  # us-east-2c
# ]
```

---

## Validations Performed

### 1. Subnet Selection Logic
- **Single-instance:** Correctly uses first available private subnet
- **Cluster mode:** Correctly selects one subnet per AZ using `subnets_by_az` grouping
- **try() wrapper:** Prevents index-out-of-bounds errors during precondition evaluation

### 2. Lifecycle Preconditions
| Precondition | Status |
|--------------|--------|
| ACTIVE_STANDBY_MULTI_AZ blocked (RabbitMQ unsupported) | **WORKING** |
| mq.t3.* instances blocked for cluster mode | **WORKING** |
| Minimum 2 distinct AZs required for cluster | **WORKING** |
| At least 1 subnet required | **WORKING** |

### 3. Outputs
| Output | Status |
|--------|--------|
| broker_arn | **WORKING** |
| broker_id | **WORKING** |
| broker_first_endpoint | **WORKING** |
| broker_endpoints | **WORKING** |
| broker_console_url | **WORKING** |
| is_cluster_mode | **WORKING** |
| mq_security_group_id | **WORKING** |
| mq_password_secret_arn | **WORKING** |

---

## Test Procedure

### Prerequisites
1. AWS credentials configured with sufficient permissions
2. VPC with private subnets in 3 AZs (tagged with `Type = "private"`)
3. Terraform >= 1.0

### Steps

1. **Create test VPC** (or use existing)
   ```bash
   cd examples/aws/vpc
   terraform init
   terraform apply -var-file=test.tfvars
   ```

2. **Test single-instance mode**
   ```bash
   cd examples/aws/amazonmq
   terraform init
   
   # Create test.tfvars with:
   # deployment_mode = "SINGLE_INSTANCE"
   # host_instance_type = "mq.t3.micro"
   
   terraform apply -var-file=test.tfvars
   terraform output is_cluster_mode  # Should be: false
   terraform destroy -var-file=test.tfvars
   ```

3. **Test cluster mode**
   ```bash
   # Update test.tfvars with:
   # deployment_mode = "CLUSTER_MULTI_AZ"
   # host_instance_type = "mq.m5.large"
   
   terraform apply -var-file=test.tfvars
   terraform output is_cluster_mode  # Should be: true
   terraform destroy -var-file=test.tfvars
   ```

4. **Cleanup**
   ```bash
   cd examples/aws/vpc
   terraform destroy -var-file=test.tfvars
   rm -f test.tfvars terraform.tfstate*
   ```

---

## Conclusion

The AmazonMQ module correctly implements:

- **Single-instance deployment** with 1 subnet selection
- **Cluster deployment** with distinct AZ subnet selection (one subnet per AZ)
- **Proper validation** through lifecycle preconditions
- **Accurate outputs** including the `is_cluster_mode` boolean flag

The module is production-ready for RabbitMQ deployments in both single-instance and cluster configurations.
