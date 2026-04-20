# environments/dev/waf/terragrunt.hcl

include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../../modules//waf"
}

dependency "alb" {
  config_path = "../alb"
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs = {
    alb_arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/mock/mock"
  }
}

inputs = {
  alb_arn              = dependency.alb.outputs.alb_arn
  rate_limit_requests  = 1000
}
