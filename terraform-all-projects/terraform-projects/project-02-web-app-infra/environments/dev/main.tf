terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws    = { source = "hashicorp/aws"; version = "~> 5.0" }
    random = { source = "hashicorp/random"; version = "~> 3.5" }
  }

  backend "s3" {
    # After running bootstrap/, fill in your bucket name and lock table name
    bucket         = "terraform-state-project02-ACCOUNT_ID"
    key            = "dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks-project02"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# ── S3 Assets Bucket ───────────────────────────────────────────────────────────

resource "aws_s3_bucket" "assets" {
  bucket = "${var.project}-${var.environment}-assets-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_versioning" "assets" {
  bucket = aws_s3_bucket.assets.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_public_access_block" "assets" {
  bucket                  = aws_s3_bucket.assets.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

# ── Networking ─────────────────────────────────────────────────────────────────

module "vpc" {
  source = "../../modules/vpc"

  project              = var.project
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  enable_nat_gateway   = var.enable_nat_gateway
  tags                 = local.common_tags
}

# ── Security Groups ────────────────────────────────────────────────────────────

module "security" {
  source = "../../modules/security"

  project     = var.project
  environment = var.environment
  vpc_id      = module.vpc.vpc_id
  tags        = local.common_tags
}

# ── Load Balancer ──────────────────────────────────────────────────────────────

module "alb" {
  source = "../../modules/alb"

  project           = var.project
  environment       = var.environment
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  alb_sg_id         = module.security.alb_sg_id
  health_check_path = var.health_check_path
  tags              = local.common_tags
}

# ── Compute ────────────────────────────────────────────────────────────────────

module "ec2" {
  source = "../../modules/ec2"

  project              = var.project
  environment          = var.environment
  vpc_id               = module.vpc.vpc_id
  private_subnet_ids   = module.vpc.private_subnet_ids
  ec2_sg_id            = module.security.ec2_sg_id
  target_group_arn     = module.alb.target_group_arn
  s3_bucket_arn        = aws_s3_bucket.assets.arn
  instance_type        = var.instance_type
  asg_min_size         = var.asg_min_size
  asg_max_size         = var.asg_max_size
  asg_desired_capacity = var.asg_desired_capacity
  tags                 = local.common_tags
}

# ── Database ───────────────────────────────────────────────────────────────────

module "rds" {
  source = "../../modules/rds"

  project              = var.project
  environment          = var.environment
  private_subnet_ids   = module.vpc.private_subnet_ids
  rds_sg_id            = module.security.rds_sg_id
  db_name              = var.db_name
  db_username          = var.db_username
  instance_class       = var.db_instance_class
  allocated_storage    = var.db_allocated_storage
  multi_az             = var.db_multi_az
  backup_retention_days = var.db_backup_retention_days
  tags                 = local.common_tags
}

# ── Locals & Data ──────────────────────────────────────────────────────────────

locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

data "aws_caller_identity" "current" {}
