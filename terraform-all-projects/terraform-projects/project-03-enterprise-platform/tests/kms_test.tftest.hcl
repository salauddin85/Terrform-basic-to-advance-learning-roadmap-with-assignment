# tests/kms_test.tftest.hcl

provider "aws" {
  region = "us-east-1"
}

run "kms_key_created_with_rotation" {
  command = apply

  module {
    source = "../modules/kms"
  }

  variables {
    project     = "test"
    environment = "test"
    aws_region  = "us-east-1"
  }

  assert {
    condition     = aws_kms_key.main.enable_key_rotation == true
    error_message = "KMS key must have automatic rotation enabled"
  }

  assert {
    condition     = aws_kms_key.main.deletion_window_in_days == 7
    error_message = "Non-prod KMS key should have a 7-day deletion window"
  }
}

run "kms_alias_created" {
  command = apply

  module {
    source = "../modules/kms"
  }

  variables {
    project     = "test"
    environment = "test"
    aws_region  = "us-east-1"
  }

  assert {
    condition     = startswith(aws_kms_alias.main.name, "alias/")
    error_message = "KMS alias must start with 'alias/'"
  }

  assert {
    condition     = aws_kms_alias.main.target_key_id == aws_kms_key.main.key_id
    error_message = "KMS alias must point to the created key"
  }
}
