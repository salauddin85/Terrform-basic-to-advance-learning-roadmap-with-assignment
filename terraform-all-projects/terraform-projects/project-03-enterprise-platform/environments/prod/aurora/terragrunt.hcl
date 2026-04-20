# environments/prod/aurora/terragrunt.hcl
# Prod: larger ACU range, 2 instances, 30-day retention, deletion_protection

include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../../modules//aurora"
}

dependency "vpc" {
  config_path = "../vpc"
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs = {
    vpc_id                  = "vpc-mock"
    private_data_subnet_ids = ["subnet-mock-1", "subnet-mock-2", "subnet-mock-3"]
  }
}

dependency "kms" {
  config_path = "../kms"
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs = { key_arn = "arn:aws:kms:us-east-1:123456789012:key/mock" }
}

dependency "ecs" {
  config_path = "../ecs"
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs = { ecs_task_sg_id = "sg-mock" }
}

inputs = {
  vpc_id          = dependency.vpc.outputs.vpc_id
  data_subnet_ids = dependency.vpc.outputs.private_data_subnet_ids
  kms_key_arn     = dependency.kms.outputs.key_arn
  ecs_task_sg_id  = dependency.ecs.outputs.ecs_task_sg_id

  # Prod: scale higher, 2 instances for reader endpoint, 30-day backup
  min_acu               = 2
  max_acu               = 32
  instance_count        = 2
  backup_retention_days = 30
  # deletion_protection and skip_final_snapshot driven by var.environment == "prod"
}
