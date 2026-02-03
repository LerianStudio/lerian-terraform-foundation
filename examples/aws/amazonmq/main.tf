# Resource to generate a random password for the broker
resource "random_password" "master" {
  length           = 16
  special          = true
  override_special = "!#$%^&*()-_+{}<>?"
}

locals {
  # Detect if this is a cluster deployment
  is_cluster = var.deployment_mode == "CLUSTER_MULTI_AZ"

  # Add mode suffix to resource name for clarity
  mode_suffix = local.is_cluster ? "cluster" : "single"
  name        = "${var.name}-${local.mode_suffix}"

  # Subnet selection logic:
  # - SINGLE_INSTANCE: 1 subnet
  # - CLUSTER_MULTI_AZ: 2-3 subnets in different AZs (RabbitMQ supports up to 3)
  subnet_ids = local.is_cluster ? slice(data.aws_subnets.private.ids, 0, min(length(data.aws_subnets.private.ids), 3)) : [data.aws_subnets.private.ids[0]]

  tags = merge(
    {
      "Name"        = local.name
      "Environment" = var.environment
    },
    var.additional_tags
  )
}

# Create a new secret for the MQ admin password
resource "aws_secretsmanager_secret" "mq_password" {
  name = "${local.name}/amazonmq-password"
  tags = local.tags
}

resource "aws_secretsmanager_secret_version" "mq_password" {
  secret_id     = aws_secretsmanager_secret.mq_password.id
  secret_string = random_password.master.result
}

# Security group for the AmazonMQ broker
resource "aws_security_group" "mq" {
  name        = "${local.name}-sg"
  description = "Allow traffic to AmazonMQ broker"
  vpc_id      = data.aws_vpc.selected.id

  tags = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "mq" {
  security_group_id = aws_security_group.mq.id
  description       = "Allow traffic to AmazonMQ broker"
  cidr_ipv4         = data.aws_vpc.selected.cidr_block
  ip_protocol       = "-1"
}

# Main AmazonMQ broker configuration
resource "aws_mq_broker" "main" {
  broker_name                = local.name
  deployment_mode            = var.deployment_mode
  engine_type                = var.engine_type
  engine_version             = var.engine_version
  host_instance_type         = var.host_instance_type
  publicly_accessible        = var.publicly_accessible
  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  subnet_ids                 = local.subnet_ids
  security_groups            = [aws_security_group.mq.id]

  user {
    username = var.mq_admin_user
    password = aws_secretsmanager_secret_version.mq_password.secret_string
  }

  tags = local.tags

  # Apply changes immediately
  apply_immediately = true

  # Enable general and audit logs
  logs {
    general = true
  }

  # Validation preconditions
  lifecycle {
    precondition {
      condition     = !(var.deployment_mode == "CLUSTER_MULTI_AZ" && can(regex("^mq\\.t3\\.", var.host_instance_type)))
      error_message = "CLUSTER_MULTI_AZ deployment mode does not support mq.t3.* instance types. Use mq.m5.large or larger."
    }

    precondition {
      condition     = !local.is_cluster || length(data.aws_subnets.private.ids) >= 2
      error_message = "CLUSTER_MULTI_AZ deployment mode requires at least 2 private subnets in different availability zones."
    }
  }
}
