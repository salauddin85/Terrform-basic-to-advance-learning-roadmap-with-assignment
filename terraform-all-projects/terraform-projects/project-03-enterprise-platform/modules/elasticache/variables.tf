variable "project"          { type = string }
variable "environment"      { type = string }
variable "vpc_id"           { type = string }
variable "data_subnet_ids"  { type = list(string) }
variable "ecs_task_sg_id"   { type = string }
variable "kms_key_arn"      { type = string }
variable "log_group_name"   { type = string }

variable "node_type"        { type = string; default = "cache.t3.micro" }
variable "num_replicas"     { type = number; default = 1 }
