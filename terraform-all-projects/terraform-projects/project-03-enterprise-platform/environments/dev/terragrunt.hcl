# environments/dev/terragrunt.hcl
# Inherits root config and adds dev-specific overrides

include "root" {
  path = find_in_parent_folders()
}
