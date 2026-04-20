variable "project"          { type = string }
variable "environment"      { type = string }
variable "vpc_id"           { type = string }
variable "data_subnet_ids"  { type = list(string) }
variable "ecs_task_sg_id"   { type = string }
variable "kms_key_arn"      { type = string }

variable "db_name"           { type = string;  default = "appdb" }
variable "db_username"       { type = string;  default = "appuser" }
variable "engine_version"    { type = string;  default = "14.9" }
variable "instance_count"    { type = number;  default = 1 }
variable "min_acu"           { type = number;  default = 0.5 }
variable "max_acu"           { type = number;  default = 4 }
variable "backup_retention_days" { type = number; default = 7 }
