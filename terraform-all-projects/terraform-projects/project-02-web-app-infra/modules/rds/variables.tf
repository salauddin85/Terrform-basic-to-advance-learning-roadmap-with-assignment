variable "project"            { type = string }
variable "environment"        { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "rds_sg_id"          { type = string }
variable "db_name"            { type = string; default = "appdb" }
variable "db_username"        { type = string; default = "appuser" }
variable "engine_version"     { type = string; default = "14.12" }
variable "instance_class"     { type = string; default = "db.t3.micro" }
variable "allocated_storage"  { type = number; default = 20 }
variable "multi_az"           { type = bool;   default = false }
variable "backup_retention_days" { type = number; default = 7 }
variable "tags"               { type = map(string); default = {} }
