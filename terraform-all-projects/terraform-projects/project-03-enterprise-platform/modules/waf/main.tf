locals {
  name_prefix = "${var.project}-${var.environment}"
  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "Terraform"
    Module      = "waf"
  }
}

# ── WAF v2 WebACL ──────────────────────────────────────────────────────────────

resource "aws_wafv2_web_acl" "main" {
  name  = "${local.name_prefix}-web-acl"
  scope = "REGIONAL" # use CLOUDFRONT for CloudFront distributions
  description = "WAF for ${local.name_prefix} ALB"

  default_action {
    allow {}
  }

  # ── Rate Limiting ────────────────────────────────────────────────────────────
  rule {
    name     = "RateLimitRule"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.rate_limit_requests
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  # ── AWS Managed Rules: Common Rule Set ───────────────────────────────────────
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 10

    override_action {
      none {} # use each rule's own action (block/count)
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"

        # Exclude rules that may cause false positives in dev
        dynamic "rule_action_override" {
          for_each = var.environment != "prod" ? ["SizeRestrictions_BODY"] : []
          content {
            name = rule_action_override.value
            action_to_use { count {} } # count instead of block in non-prod
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-common-rules"
      sampled_requests_enabled   = true
    }
  }

  # ── AWS Managed Rules: Known Bad Inputs ──────────────────────────────────────
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 20

    override_action { none {} }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  # ── AWS Managed Rules: SQL Injection ─────────────────────────────────────────
  rule {
    name     = "AWSManagedRulesSQLiRuleSet"
    priority = 30

    override_action { none {} }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-sqli"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name_prefix}-web-acl"
    sampled_requests_enabled   = true
  }

  tags = local.common_tags
}

# ── Attach WAF to ALB ──────────────────────────────────────────────────────────

resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = var.alb_arn
  web_acl_arn  = aws_wafv2_web_acl.main.arn
}

# ── WAF Logging ───────────────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "waf" {
  # WAF log group names MUST start with "aws-waf-logs-"
  name              = "aws-waf-logs-${local.name_prefix}"
  retention_in_days = 90

  tags = local.common_tags
}

resource "aws_wafv2_web_acl_logging_configuration" "main" {
  log_destination_configs = [aws_cloudwatch_log_group.waf.arn]
  resource_arn            = aws_wafv2_web_acl.main.arn

  # Redact sensitive fields from logs
  redacted_fields {
    single_header { name = "authorization" }
  }
  redacted_fields {
    single_header { name = "cookie" }
  }
}
