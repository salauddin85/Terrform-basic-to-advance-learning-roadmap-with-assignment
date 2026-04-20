variable "project"     { type = string }
variable "environment" { type = string }
variable "aws_region"  { type = string; default = "us-east-1" }
variable "vpc_cidr"    { type = string; default = "10.0.0.0/16" }
variable "kms_key_arn" { type = string }

variable "azs" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b"]
}
