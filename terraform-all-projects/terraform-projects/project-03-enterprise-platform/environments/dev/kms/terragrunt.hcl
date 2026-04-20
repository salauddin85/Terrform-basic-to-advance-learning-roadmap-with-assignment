# environments/dev/kms/terragrunt.hcl

include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../../modules//kms"
}

inputs = {
  # project, environment, aws_region injected from root terragrunt.hcl
}
