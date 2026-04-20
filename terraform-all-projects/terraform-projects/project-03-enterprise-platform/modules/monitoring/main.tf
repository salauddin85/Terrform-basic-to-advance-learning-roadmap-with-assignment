locals {
  name_prefix = "${var.project}-${var.environment}"
  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "Terraform"
    Module      = "monitoring"
  }
}

# ── SNS Topic for Alarms ───────────────────────────────────────────────────────

resource "aws_sns_topic" "alarms" {
  name              = "${local.name_prefix}-alarms"
  kms_master_key_id = var.kms_key_arn

  tags = local.common_tags
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alarm_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# ── CloudWatch Alarms ──────────────────────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "ecs_cpu_high" {
  alarm_name          = "${local.name_prefix}-ecs-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 120
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "ECS CPU utilization > 80%"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = var.ecs_service_name
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "alb_5xx_high" {
  alarm_name          = "${local.name_prefix}-alb-5xx-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 10
  alarm_description   = "ALB 5xx errors > 10 in 1 minute"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  metric_query {
    id          = "error_rate"
    expression  = "errors/requests*100"
    label       = "5xx Error Rate"
    return_data = true
  }

  metric_query {
    id = "errors"
    metric {
      metric_name = "HTTPCode_Target_5XX_Count"
      namespace   = "AWS/ApplicationELB"
      period      = 60
      stat        = "Sum"
      dimensions  = { LoadBalancer = var.alb_arn_suffix }
    }
  }

  metric_query {
    id = "requests"
    metric {
      metric_name = "RequestCount"
      namespace   = "AWS/ApplicationELB"
      period      = 60
      stat        = "Sum"
      dimensions  = { LoadBalancer = var.alb_arn_suffix }
    }
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "aurora_connections_high" {
  alarm_name          = "${local.name_prefix}-aurora-connections-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 120
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Aurora connection count > 80"
  alarm_actions       = [aws_sns_topic.alarms.arn]

  dimensions = { DBClusterIdentifier = var.aurora_cluster_id }

  tags = local.common_tags
}

# ── CloudWatch Dashboard ───────────────────────────────────────────────────────

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${local.name_prefix}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0; y = 0; width = 12; height = 6
        properties = {
          title  = "ECS CPU & Memory Utilization"
          period = 60
          metrics = [
            ["AWS/ECS", "CPUUtilization",    "ClusterName", var.ecs_cluster_name, "ServiceName", var.ecs_service_name],
            ["AWS/ECS", "MemoryUtilization", "ClusterName", var.ecs_cluster_name, "ServiceName", var.ecs_service_name],
          ]
          view = "timeSeries"
          stat = "Average"
        }
      },
      {
        type   = "metric"
        x      = 12; y = 0; width = 12; height = 6
        properties = {
          title  = "ALB Request Count & Latency"
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "RequestCount",        "LoadBalancer", var.alb_arn_suffix],
            ["AWS/ApplicationELB", "TargetResponseTime",  "LoadBalancer", var.alb_arn_suffix],
          ]
          view = "timeSeries"
          stat = "Sum"
        }
      },
      {
        type   = "metric"
        x      = 0; y = 6; width = 12; height = 6
        properties = {
          title  = "Aurora DB Connections & CPU"
          period = 60
          metrics = [
            ["AWS/RDS", "DatabaseConnections", "DBClusterIdentifier", var.aurora_cluster_id],
            ["AWS/RDS", "CPUUtilization",       "DBClusterIdentifier", var.aurora_cluster_id],
          ]
          view = "timeSeries"
          stat = "Average"
        }
      },
      {
        type   = "metric"
        x      = 12; y = 6; width = 12; height = 6
        properties = {
          title  = "Redis Cache Hit Rate"
          period = 60
          metrics = [
            ["AWS/ElastiCache", "CacheHits",   "ReplicationGroupId", var.redis_replication_group_id],
            ["AWS/ElastiCache", "CacheMisses", "ReplicationGroupId", var.redis_replication_group_id],
          ]
          view = "timeSeries"
          stat = "Sum"
        }
      }
    ]
  })
}
