variable "project"           { type = string }
variable "environment"       { type = string }
variable "vpc_id"            { type = string }
variable "public_subnet_ids" { type = list(string) }
variable "container_port"    { type = number; default = 80 }
variable "health_check_path" { type = string; default = "/health" }
# variable "acm_certificate_arn" { type = string }  # uncomment for HTTPS
