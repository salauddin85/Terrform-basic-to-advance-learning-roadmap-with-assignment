variable "project"                    { type = string }
variable "environment"                { type = string }
variable "kms_key_arn"                { type = string }
variable "ecs_cluster_name"           { type = string }
variable "ecs_service_name"           { type = string }
variable "alb_arn_suffix"             { type = string }
variable "aurora_cluster_id"          { type = string }
variable "redis_replication_group_id" { type = string }
variable "alarm_email"                { type = string; default = "" }
