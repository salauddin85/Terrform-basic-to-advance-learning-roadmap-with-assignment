variable "project"          { type = string }
variable "environment"      { type = string }
variable "vpc_id"           { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "ec2_sg_id"        { type = string }
variable "target_group_arn" { type = string }
variable "s3_bucket_arn"    { type = string }
variable "instance_type"    { type = string; default = "t3.micro" }
variable "asg_min_size"     { type = number; default = 1 }
variable "asg_max_size"     { type = number; default = 3 }
variable "asg_desired_capacity" { type = number; default = 2 }
variable "tags"             { type = map(string); default = {} }
