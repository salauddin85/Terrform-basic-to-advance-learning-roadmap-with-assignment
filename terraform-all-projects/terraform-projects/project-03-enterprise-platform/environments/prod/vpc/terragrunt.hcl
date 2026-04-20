# environments/prod/vpc/terragrunt.hcl
# Prod uses 3 AZs and one NAT Gateway per AZ for high availability

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
  vpc_cidr    = "10.1.0.0/16"   # different CIDR from dev to allow VPC peering
  azs         = ["us-east-1a", "us-east-1b", "us-east-1c"]
  kms_key_arn = dependency.kms.outputs.key_arn
  # environment = "prod" triggers one-NAT-per-AZ logic inside the module
}
