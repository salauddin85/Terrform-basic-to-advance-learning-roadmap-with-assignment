variable "project"           { type = string }
variable "environment"       { type = string }
variable "vpc_id"            { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "alb_sg_id"         { type = string }
variable "target_group_arn"  { type = string }
variable "kms_key_arn"       { type = string }
variable "s3_bucket_arn"     { type = string }
variable "db_secret_arn"     { type = string }

variable "container_image"  { type = string; default = "nginx:latest" }
variable "container_port"   { type = number; default = 80 }
variable "task_cpu"         { type = number; default = 256 }
variable "task_memory"      { type = number; default = 512 }
variable "desired_count"    { type = number; default = 2 }
variable "min_capacity"     { type = number; default = 1 }
variable "max_capacity"     { type = number; default = 6 }
