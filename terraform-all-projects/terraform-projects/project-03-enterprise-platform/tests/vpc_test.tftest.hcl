# tests/vpc_test.tftest.hcl
# Run with: terraform test
# These tests provision REAL infrastructure and destroy it after — ~5 min

provider "aws" {
  region = "us-east-1"
}

# ── Test 1: Basic VPC creation ────────────────────────────────────────────────
run "vpc_is_created_with_correct_cidr" {
  command = apply

  module {
    source = "../modules/vpc"
  }

  variables {
    project     = "test"
    environment = "test"
    vpc_cidr    = "10.99.0.0/16"
    kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/test"  # mock — kms not tested here
    azs         = ["us-east-1a", "us-east-1b"]
  }

  assert {
    condition     = aws_vpc.main.cidr_block == "10.99.0.0/16"
    error_message = "VPC CIDR block does not match expected value '10.99.0.0/16'"
  }

  assert {
    condition     = aws_vpc.main.enable_dns_hostnames == true
    error_message = "DNS hostnames must be enabled on the VPC"
  }

  assert {
    condition     = aws_vpc.main.enable_dns_support == true
    error_message = "DNS support must be enabled on the VPC"
  }
}

# ── Test 2: Subnet count and tiers ────────────────────────────────────────────
run "correct_number_of_subnets_created" {
  command = apply

  module {
    source = "../modules/vpc"
  }

  variables {
    project     = "test"
    environment = "test"
    vpc_cidr    = "10.99.0.0/16"
    kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/test"
    azs         = ["us-east-1a", "us-east-1b"]
  }

  assert {
    condition     = length(aws_subnet.public) == 2
    error_message = "Expected 2 public subnets, got ${length(aws_subnet.public)}"
  }

  assert {
    condition     = length(aws_subnet.private_app) == 2
    error_message = "Expected 2 private-app subnets, got ${length(aws_subnet.private_app)}"
  }

  assert {
    condition     = length(aws_subnet.private_data) == 2
    error_message = "Expected 2 private-data subnets, got ${length(aws_subnet.private_data)}"
  }
}

# ── Test 3: Public subnets map public IPs ─────────────────────────────────────
run "public_subnets_assign_public_ips" {
  command = apply

  module {
    source = "../modules/vpc"
  }

  variables {
    project     = "test"
    environment = "test"
    vpc_cidr    = "10.99.0.0/16"
    kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/test"
    azs         = ["us-east-1a", "us-east-1b"]
  }

  assert {
    condition     = alltrue([for s in aws_subnet.public : s.map_public_ip_on_launch == true])
    error_message = "All public subnets must have map_public_ip_on_launch = true"
  }

  assert {
    condition     = alltrue([for s in aws_subnet.private_app : s.map_public_ip_on_launch == false])
    error_message = "Private app subnets must NOT have map_public_ip_on_launch"
  }

  assert {
    condition     = alltrue([for s in aws_subnet.private_data : s.map_public_ip_on_launch == false])
    error_message = "Private data subnets must NOT have map_public_ip_on_launch"
  }
}

# ── Test 4: Internet Gateway attached ─────────────────────────────────────────
run "internet_gateway_attached_to_vpc" {
  command = apply

  module {
    source = "../modules/vpc"
  }

  variables {
    project     = "test"
    environment = "test"
    vpc_cidr    = "10.99.0.0/16"
    kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/test"
    azs         = ["us-east-1a", "us-east-1b"]
  }

  assert {
    condition     = aws_internet_gateway.main.vpc_id == aws_vpc.main.id
    error_message = "Internet gateway must be attached to the VPC"
  }
}

# ── Test 5: Tags applied correctly ───────────────────────────────────────────
run "resources_are_tagged_correctly" {
  command = apply

  module {
    source = "../modules/vpc"
  }

  variables {
    project     = "test"
    environment = "test"
    vpc_cidr    = "10.99.0.0/16"
    kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/test"
    azs         = ["us-east-1a", "us-east-1b"]
  }

  assert {
    condition     = aws_vpc.main.tags["Environment"] == "test"
    error_message = "VPC must have Environment tag set to 'test'"
  }

  assert {
    condition     = aws_vpc.main.tags["ManagedBy"] == "Terraform"
    error_message = "VPC must have ManagedBy = 'Terraform' tag"
  }

  assert {
    condition     = aws_vpc.main.tags["Project"] == "test"
    error_message = "VPC must have Project tag"
  }
}

# ── Test 6: Data subnet has NO default internet route ─────────────────────────
run "data_subnet_has_no_internet_route" {
  command = apply

  module {
    source = "../modules/vpc"
  }

  variables {
    project     = "test"
    environment = "test"
    vpc_cidr    = "10.99.0.0/16"
    kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/test"
    azs         = ["us-east-1a", "us-east-1b"]
  }

  assert {
    condition = !anytrue([
      for route in aws_route_table.private_data.route :
      route.cidr_block == "0.0.0.0/0"
    ])
    error_message = "Data subnet route table must NOT have a default internet route (0.0.0.0/0)"
  }
}
