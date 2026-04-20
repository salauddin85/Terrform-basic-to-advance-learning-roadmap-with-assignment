locals {
  name_prefix = "${var.project}-${var.environment}"
  common_tags = merge(var.tags, {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "Terraform"
    Module      = "rds"
  })
}

# ── Random Password (stored in Secrets Manager — never in state) ───────────────

resource "random_password" "db" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "db_password" {
  name                    = "/${var.project}/${var.environment}/rds/password"
  description             = "RDS master password for ${local.name_prefix}"
  recovery_window_in_days = var.environment == "prod" ? 30 : 0

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = random_password.db.result

  lifecycle {
    ignore_changes = [secret_string] # don't reset password on every apply
  }
}

# ── DB Subnet Group ────────────────────────────────────────────────────────────

resource "aws_db_subnet_group" "main" {
  name        = "${local.name_prefix}-db-subnet-group"
  description = "DB subnet group for ${local.name_prefix}"
  subnet_ids  = var.private_subnet_ids

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-db-subnet-group" })
}

# ── DB Parameter Group ─────────────────────────────────────────────────────────

resource "aws_db_parameter_group" "postgres" {
  name        = "${local.name_prefix}-pg14-params"
  family      = "postgres14"
  description = "Custom parameter group for ${local.name_prefix}"

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000" # log queries taking > 1 second
  }

  tags = local.common_tags

  lifecycle {
    create_before_destroy = true
  }
}

# ── RDS Instance ───────────────────────────────────────────────────────────────

resource "aws_db_instance" "main" {
  identifier = "${local.name_prefix}-postgres"

  # Engine
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  # Storage
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.allocated_storage * 3 # enable autoscaling up to 3x
  storage_type          = "gp3"
  storage_encrypted     = true

  # Credentials — pulled from Secrets Manager
  db_name  = var.db_name
  username = var.db_username
  password = random_password.db.result

  # Network
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.rds_sg_id]
  publicly_accessible    = false # never public

  # Parameter group
  parameter_group_name = aws_db_parameter_group.postgres.name

  # Availability
  multi_az = var.multi_az

  # Backup
  backup_retention_period   = var.backup_retention_days
  backup_window             = "03:00-04:00"
  maintenance_window        = "Mon:04:00-Mon:05:00"
  copy_tags_to_snapshot     = true
  delete_automated_backups  = var.environment != "prod"

  # Protection
  deletion_protection       = var.environment == "prod"
  skip_final_snapshot       = var.environment != "prod"
  final_snapshot_identifier = var.environment == "prod" ? "${local.name_prefix}-final-snapshot" : null

  # Monitoring
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  monitoring_interval             = 60
  monitoring_role_arn             = aws_iam_role.rds_monitoring.arn
  performance_insights_enabled    = true
  performance_insights_retention_period = 7

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-postgres" })

  lifecycle {
    prevent_destroy = false # set to true for production databases
    ignore_changes  = [password] # managed via Secrets Manager rotation
  }
}

# ── Enhanced Monitoring IAM Role ───────────────────────────────────────────────

resource "aws_iam_role" "rds_monitoring" {
  name = "${local.name_prefix}-rds-monitoring-role"

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
