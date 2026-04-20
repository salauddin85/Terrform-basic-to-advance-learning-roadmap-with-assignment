# environments/dev/vpc/terragrunt.hcl

include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../../modules//vpc"
}

dependency "kms" {
  config_path = "../kms"

  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs = {
    key_arn = "arn:aws:kms:us-east-1:123456789012:key/mock-key-id"
  }
}

inputs = {
  vpc_cidr    = "10.0.0.0/16"
  azs         = ["us-east-1a", "us-east-1b"]
  kms_key_arn = dependency.kms.outputs.key_arn
}
