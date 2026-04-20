locals {
  name_prefix = "${var.project}-${var.environment}"
  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "Terraform"
    Module      = "aurora"
  }
}

# ── Random Password → Secrets Manager ─────────────────────────────────────────

resource "random_password" "aurora" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "aurora_password" {
  name                    = "/${var.project}/${var.environment}/aurora/password"
  description             = "Aurora master password for ${local.name_prefix}"
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = var.environment == "prod" ? 30 : 0

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "aurora_password" {
  secret_id = aws_secretsmanager_secret.aurora_password.id

  secret_string = jsonencode({
    username = var.db_username
    password = random_password.aurora.result
    engine   = "postgres"
    host     = aws_rds_cluster.main.endpoint
    port     = 5432
    dbname   = var.db_name
  })

  lifecycle {
    ignore_changes = [secret_string] # don't rotate on every apply
  }
}

# ── Subnet Group ───────────────────────────────────────────────────────────────

resource "aws_db_subnet_group" "aurora" {
  name        = "${local.name_prefix}-aurora-subnet-group"
  description = "Aurora subnet group for ${local.name_prefix}"
  subnet_ids  = var.data_subnet_ids

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-aurora-subnet-group" })
}

# ── Security Group ─────────────────────────────────────────────────────────────

resource "aws_security_group" "aurora" {
  name        = "${local.name_prefix}-aurora-sg"
  description = "Aurora — allow PostgreSQL from ECS tasks only"
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-aurora-sg" })

  lifecycle { create_before_destroy = true }
}

resource "aws_vpc_security_group_ingress_rule" "aurora_from_ecs" {
  security_group_id            = aws_security_group.aurora.id
  description                  = "PostgreSQL from ECS tasks only"
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  referenced_security_group_id = var.ecs_task_sg_id
}

# ── Parameter Group ────────────────────────────────────────────────────────────

resource "aws_rds_cluster_parameter_group" "aurora" {
  name        = "${local.name_prefix}-aurora-pg14-params"
  family      = "aurora-postgresql14"
  description = "Aurora PostgreSQL 14 params for ${local.name_prefix}"

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  parameter {
    name  = "log_connections"
    value = "1"
  }

  tags = local.common_tags

  lifecycle { create_before_destroy = true }
}

# ── Aurora Cluster ─────────────────────────────────────────────────────────────

resource "aws_rds_cluster" "main" {
  cluster_identifier = "${local.name_prefix}-aurora"

  engine         = "aurora-postgresql"
  engine_version = var.engine_version
  engine_mode    = "provisioned" # required for Serverless v2

  database_name   = var.db_name
  master_username = var.db_username
  master_password = random_password.aurora.result

  db_subnet_group_name            = aws_db_subnet_group.aurora.name
  vpc_security_group_ids          = [aws_security_group.aurora.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.aurora.name

  # Encryption
  storage_encrypted = true
  kms_key_id        = var.kms_key_arn

  # Serverless v2 scaling — key configuration
  serverlessv2_scaling_configuration {
    min_capacity = var.min_acu
    max_capacity = var.max_acu
  }

  # Backup
  backup_retention_period   = var.backup_retention_days
  preferred_backup_window   = "03:00-04:00"
  copy_tags_to_snapshot     = true
  skip_final_snapshot       = var.environment != "prod"
  final_snapshot_identifier = var.environment == "prod" ? "${local.name_prefix}-aurora-final" : null

  # Logging
  enabled_cloudwatch_logs_exports = ["postgresql"]

  # Protection
  deletion_protection = var.environment == "prod"

  # Allow minor version upgrades automatically
  allow_major_version_upgrade = false

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-aurora" })

  lifecycle {
    ignore_changes = [master_password] # managed via Secrets Manager
  }
}

# ── Aurora Cluster Instance (required even for Serverless v2) ─────────────────

resource "aws_rds_cluster_instance" "main" {
  count = var.instance_count

  identifier         = "${local.name_prefix}-aurora-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.main.id
  instance_class     = "db.serverless" # magic value for Serverless v2
  engine             = aws_rds_cluster.main.engine
  engine_version     = aws_rds_cluster.main.engine_version

  performance_insights_enabled          = true
  performance_insights_kms_key_id       = var.kms_key_arn
  performance_insights_retention_period = 7

  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  auto_minor_version_upgrade = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-aurora-instance-${count.index + 1}"
  })
}

# ── Enhanced Monitoring IAM Role ───────────────────────────────────────────────

resource "aws_iam_role" "rds_monitoring" {
  name = "${local.name_prefix}-aurora-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}
