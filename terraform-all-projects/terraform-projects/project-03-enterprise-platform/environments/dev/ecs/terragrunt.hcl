# environments/dev/ecs/terragrunt.hcl

include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../../modules//ecs"
}

dependency "vpc" {
  config_path = "../vpc"
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs = {
    vpc_id                 = "vpc-mock"
    private_app_subnet_ids = ["subnet-mock-1", "subnet-mock-2"]
  }
}

dependency "alb" {
  config_path = "../alb"
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs = {
    alb_sg_id        = "sg-mock-alb"
    target_group_arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/mock/mock"
  }
}

dependency "kms" {
  config_path = "../kms"
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs = { key_arn = "arn:aws:kms:us-east-1:123456789012:key/mock" }
}

dependency "aurora" {
  config_path = "../aurora"
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs = {
    secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:mock"
  }
}

locals {
  account_id = get_aws_account_id()
  region     = "us-east-1"
}

inputs = {
  vpc_id             = dependency.vpc.outputs.vpc_id
  private_subnet_ids = dependency.vpc.outputs.private_app_subnet_ids
  alb_sg_id          = dependency.alb.outputs.alb_sg_id
  target_group_arn   = dependency.alb.outputs.target_group_arn
  kms_key_arn        = dependency.kms.outputs.key_arn
  db_secret_arn      = dependency.aurora.outputs.secret_arn

  # Dev: use nginx as a stand-in for your real application image
  s3_bucket_arn   = "arn:aws:s3:::placeholder"   # replace with real bucket
  container_image = "nginx:latest"
  container_port  = 80
  task_cpu        = 256
  task_memory     = 512
  desired_count   = 1
  min_capacity    = 1
  max_capacity    = 3
}
