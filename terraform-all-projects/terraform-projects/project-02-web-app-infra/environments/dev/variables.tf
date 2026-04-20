variable "aws_region"   { type = string; default = "us-east-1" }
variable "project"      { type = string }
variable "environment"  { type = string }

variable "vpc_cidr"             { type = string; default = "10.0.0.0/16" }
variable "public_subnet_cidrs"  { type = list(string) }
variable "private_subnet_cidrs" { type = list(string) }
variable "enable_nat_gateway"   { type = bool; default = false }

variable "instance_type"        { type = string; default = "t3.micro" }
variable "asg_min_size"         { type = number; default = 1 }
variable "asg_max_size"         { type = number; default = 3 }
variable "asg_desired_capacity" { type = number; default = 2 }
variable "health_check_path"    { type = string; default = "/" }

variable "db_name"                 { type = string; default = "appdb" }
variable "db_username"             { type = string; default = "appuser" }
variable "db_instance_class"       { type = string; default = "db.t3.micro" }
variable "db_allocated_storage"    { type = number; default = 20 }
variable "db_multi_az"             { type = bool;   default = false }
variable "db_backup_retention_days" { type = number; default = 7 }
