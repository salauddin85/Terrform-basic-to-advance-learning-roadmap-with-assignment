# ── Root Terragrunt Configuration ─────────────────────────────────────────────
# This file is inherited by ALL modules in ALL environments.
# It auto-generates backend.tf so you never copy-paste it again.

locals {
  # Parse the environment from the directory structure
  # e.g. environments/dev/vpc → environment = "dev"
  env_vars    = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment = local.env_vars.locals.environment
  aws_region  = local.env_vars.locals.aws_region
  project     = local.env_vars.locals.project
  account_id  = get_aws_account_id()
}

# Auto-generate backend.tf in every module directory
remote_state {
  backend = "s3"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    bucket         = "${local.project}-terraform-state-${local.account_id}"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = local.aws_region
    dynamodb_table = "${local.project}-terraform-locks"
    encrypt        = true
  }
}

# Auto-generate provider.tf in every module directory
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"

  contents = <<-EOF
    provider "aws" {
      region = "${local.aws_region}"

      default_tags {
        tags = {
          Project     = "${local.project}"
          Environment = "${local.environment}"
          ManagedBy   = "Terraform"
          ManagedWith = "Terragrunt"
        }
      }
    }
  EOF
}

# Common inputs passed to every module
inputs = {
  project     = local.project
  environment = local.environment
  aws_region  = local.aws_region
}
