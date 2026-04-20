# environments/dev/elasticache/terragrunt.hcl

include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../../modules//elasticache"
}

dependency "vpc" {
  config_path = "../vpc"
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs = {
    vpc_id                  = "vpc-mock"
    private_data_subnet_ids = ["subnet-mock-1", "subnet-mock-2"]
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
  mock_outputs = {
    ecs_task_sg_id  = "sg-mock"
    log_group_name  = "/ecs/mock"
  }
}

inputs = {
  vpc_id          = dependency.vpc.outputs.vpc_id
  data_subnet_ids = dependency.vpc.outputs.private_data_subnet_ids
  kms_key_arn     = dependency.kms.outputs.key_arn
  ecs_task_sg_id  = dependency.ecs.outputs.ecs_task_sg_id
  log_group_name  = dependency.ecs.outputs.log_group_name

  # Dev: smallest node, single replica
  node_type    = "cache.t3.micro"
  num_replicas = 0
}
