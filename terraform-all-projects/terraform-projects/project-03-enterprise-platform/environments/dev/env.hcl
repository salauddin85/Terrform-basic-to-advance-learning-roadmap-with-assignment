# environments/dev/env.hcl
# Environment-level config — inherited by all modules in this environment

locals {
  environment = "dev"
  aws_region  = "us-east-1"
  project     = "enterprise"
}
