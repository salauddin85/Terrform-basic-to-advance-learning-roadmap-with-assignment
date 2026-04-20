locals {
  name_prefix = "${var.project}-${var.environment}"
  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "Terraform"
    Module      = "kms"
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ── Customer-Managed KMS Key ───────────────────────────────────────────────────

data "aws_iam_policy_document" "kms_policy" {
  # Root account admin access — REQUIRED, without this you can lock yourself out
  statement {
    sid    = "EnableRootAccountPermissions"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  # Allow CloudWatch Logs to use the key
  statement {
    sid    = "AllowCloudWatchLogs"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["logs.${data.aws_region.current.name}.amazonaws.com"]
    }
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = ["*"]
  }

  # Allow Secrets Manager to use the key
  statement {
    sid    = "AllowSecretsManager"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["secretsmanager.amazonaws.com"]
    }
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey",
    ]
    resources = ["*"]
  }
}

resource "aws_kms_key" "main" {
  description             = "${local.name_prefix} — primary encryption key"
  deletion_window_in_days = var.environment == "prod" ? 30 : 7
  enable_key_rotation     = true # rotate annually — security best practice
  policy                  = data.aws_iam_policy_document.kms_policy.json

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-key" })
}

resource "aws_kms_alias" "main" {
  name          = "alias/${local.name_prefix}"
  target_key_id = aws_kms_key.main.key_id
}
