locals {
  name_prefix = "${var.project}-${var.environment}"
  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "Terraform"
    Module      = "elasticache"
  }
}

# ── Auth Token → Secrets Manager ──────────────────────────────────────────────

resource "random_password" "redis_auth" {
  length  = 32
  special = false # Redis auth tokens cannot contain special chars
}

resource "aws_secretsmanager_secret" "redis_auth" {
  name                    = "/${var.project}/${var.environment}/redis/auth-token"
  description             = "Redis auth token for ${local.name_prefix}"
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = 0

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "redis_auth" {
  secret_id     = aws_secretsmanager_secret.redis_auth.id
  secret_string = random_password.redis_auth.result

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# ── Subnet Group ───────────────────────────────────────────────────────────────

resource "aws_elasticache_subnet_group" "redis" {
  name        = "${local.name_prefix}-redis-subnet-group"
  description = "Redis subnet group for ${local.name_prefix}"
  subnet_ids  = var.data_subnet_ids

  tags = local.common_tags
}

# ── Security Group ─────────────────────────────────────────────────────────────

resource "aws_security_group" "redis" {
  name        = "${local.name_prefix}-redis-sg"
  description = "Redis — allow access from ECS tasks only"
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-redis-sg" })

  lifecycle { create_before_destroy = true }
}

resource "aws_vpc_security_group_ingress_rule" "redis_from_ecs" {
  security_group_id            = aws_security_group.redis.id
  description                  = "Redis from ECS tasks only"
  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"
  referenced_security_group_id = var.ecs_task_sg_id
}

# ── Parameter Group ────────────────────────────────────────────────────────────

resource "aws_elasticache_parameter_group" "redis" {
  name        = "${local.name_prefix}-redis7-params"
  family      = "redis7"
  description = "Redis 7 parameters for ${local.name_prefix}"

  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru" # evict least recently used keys when memory full
  }

  tags = local.common_tags

  lifecycle { create_before_destroy = true }
}

# ── Redis Replication Group ────────────────────────────────────────────────────

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id = "${local.name_prefix}-redis"
  description          = "Redis cluster for ${local.name_prefix}"

  # Engine
  engine               = "redis"
  engine_version       = "7.0"
  node_type            = var.node_type
  parameter_group_name = aws_elasticache_parameter_group.redis.name
  port                 = 6379

  # Topology
  num_cache_clusters = var.num_replicas + 1 # primary + replicas

  # Network
  subnet_group_name  = aws_elasticache_subnet_group.redis.name
  security_group_ids = [aws_security_group.redis.id]

  # Security — in-transit and at-rest encryption
  at_rest_encryption_enabled  = true
  transit_encryption_enabled  = true
  auth_token                  = random_password.redis_auth.result
  kms_key_id                  = var.kms_key_arn

  # Maintenance
  automatic_failover_enabled = var.num_replicas > 0
  maintenance_window         = "sun:05:00-sun:06:00"
  snapshot_window            = "04:00-05:00"
  snapshot_retention_limit   = var.environment == "prod" ? 7 : 1

  apply_immediately = var.environment != "prod"

  log_delivery_configuration {
    destination      = var.log_group_name
    destination_type = "cloudwatch-logs"
    log_format       = "text"
    log_type         = "slow-log"
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-redis" })
}
