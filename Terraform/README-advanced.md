# Terraform Training — Level 3: Advanced
> **Prerequisites:** Level 1 + Level 2 complete, both assignments passed  
> **Goal:** Engineer production-grade Terraform at scale — secure, tested, observable, and enterprise-ready  
> **Time estimate:** 4–5 days  
> **Tutor:** Senior DevOps Engineer (10 years experience)

---

## What Changes at This Level

Levels 1 and 2 taught you to build infrastructure correctly. Level 3 teaches you to build it at scale, safely, and sustainably. You will learn:
- Patterns used by companies managing hundreds of AWS accounts
- How to test infrastructure code before it reaches production
- How to prevent and detect configuration drift
- Security hardening at the Terraform layer
- Dynamic, DRY configuration that handles complex real-world requirements

This is what separates a DevOps engineer from a senior one.

---

## Table of Contents
1. [Advanced Variable Patterns](#step-1-advanced-variable-patterns)
2. [Dynamic Blocks & Expressions](#step-2-dynamic-blocks--expressions)
3. [Terraform Functions Deep Dive](#step-3-terraform-functions-deep-dive)
4. [Security Hardening](#step-4-security-hardening)
5. [Testing Terraform Code](#step-5-testing-terraform-code)
6. [Drift Detection & Remediation](#step-6-drift-detection--remediation)
7. [Terragrunt — DRY at Scale](#step-7-terragrunt--dry-at-scale)
8. [Managing Secrets](#step-8-managing-secrets)
9. [Enterprise Patterns](#step-9-enterprise-patterns)
10. [Level 3 Final Assignment](#level-3-final-assignment)

---

## Step 1: Advanced Variable Patterns

### Complex types: object and list(object)

```hcl
# Group all RDS configuration into one structured variable
variable "rds_config" {
  type = object({
    instance_class          = string
    allocated_storage       = number
    engine_version          = string
    multi_az                = bool
    backup_retention_days   = number
    deletion_protection     = bool
    performance_insights    = optional(bool, false)   # optional with default
    parameter_group_family  = optional(string, "postgres14")
  })
  default = {
    instance_class         = "db.t3.micro"
    allocated_storage      = 20
    engine_version         = "14.9"
    multi_az               = false
    backup_retention_days  = 7
    deletion_protection    = false
  }
}

# Create multiple security group rules from a structured list
variable "ingress_rules" {
  type = list(object({
    port        = number
    protocol    = string
    cidr_blocks = list(string)
    description = string
  }))
  default = [
    {
      port        = 80
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
      description = "HTTP from internet"
    },
    {
      port        = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
      description = "HTTPS from internet"
    },
    {
      port        = 22
      protocol    = "tcp"
      cidr_blocks = ["10.0.0.0/8"]
      description = "SSH from VPN only"
    }
  ]
}
```

### Validation — enforce rules at plan time, not after deploy

```hcl
variable "environment" {
  type    = string
  default = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block (e.g. 10.0.0.0/16)."
  }
}

variable "instance_type" {
  type    = string
  default = "t3.micro"

  validation {
    condition     = can(regex("^(t3|t3a|m5|m5a|c5)\\..+", var.instance_type))
    error_message = "Only t3, t3a, m5, m5a, or c5 instance families are approved for use."
  }
}

variable "rds_password" {
  type      = string
  sensitive = true   # never logged, never shown in plan output

  validation {
    condition     = length(var.rds_password) >= 16
    error_message = "RDS password must be at least 16 characters."
  }
}
```

### `sensitive` — protect secrets in output

```hcl
variable "db_password" {
  type      = string
  sensitive = true
}

output "db_connection_string" {
  value     = "postgresql://app:${var.db_password}@${aws_db_instance.main.endpoint}/app"
  sensitive = true   # hides the value in terraform apply output
}
```

---

## Step 2: Dynamic Blocks & Expressions

### Dynamic blocks — generate repeated nested blocks programmatically

Without dynamic blocks, adding a new ingress rule means copy-pasting a block. With dynamic blocks, you loop.

```hcl
# Instead of manually writing each ingress block...
resource "aws_security_group" "web" {
  name = "web-sg"

  # BEFORE (manual — doesn't scale):
  # ingress { from_port = 80 ... }
  # ingress { from_port = 443 ... }
  # ingress { from_port = 22 ... }

  # AFTER (dynamic — scales to any number of rules):
  dynamic "ingress" {
    for_each = var.ingress_rules

    content {
      from_port   = ingress.value.port
      to_port     = ingress.value.port
      protocol    = ingress.value.protocol
      cidr_blocks = ingress.value.cidr_blocks
      description = ingress.value.description
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

### Conditional dynamic block

```hcl
resource "aws_db_instance" "main" {
  identifier     = "${var.environment}-postgres"
  instance_class = var.rds_config.instance_class
  engine         = "postgres"

  # Only add restore config if a snapshot ID is provided
  dynamic "restore_to_point_in_time" {
    for_each = var.db_snapshot_id != null ? [var.db_snapshot_id] : []
    content {
      source_db_instance_identifier = restore_to_point_in_time.value
    }
  }
}
```

### For expressions — transform lists and maps

```hcl
# Transform a list of strings to uppercase
variable "environments" {
  default = ["dev", "staging", "prod"]
}

locals {
  env_upper = [for e in var.environments : upper(e)]
  # → ["DEV", "STAGING", "PROD"]

  # Filter a list — only production-like environments
  prod_envs = [for e in var.environments : e if e != "dev"]
  # → ["staging", "prod"]

  # Transform a list to a map (for for_each)
  env_cidr_map = {
    for idx, env in var.environments :
    env => "10.${idx}.0.0/16"
  }
  # → { dev = "10.0.0.0/16", staging = "10.1.0.0/16", prod = "10.2.0.0/16" }

  # Invert a map
  instance_type_map = { t2.micro = "cheap", t3.large = "standard" }
  inverted = { for k, v in local.instance_type_map : v => k }
  # → { cheap = "t2.micro", standard = "t3.large" }

  # Flatten nested list of subnet IDs from multiple VPCs
  all_private_subnets = flatten([
    for vpc in var.vpcs : vpc.private_subnet_ids
  ])
}
```

### The `one()` function — safely unwrap single-item lists

```hcl
# count returns a list — use one() when you expect 0 or 1 items
resource "aws_nat_gateway" "main" {
  count = var.enable_nat ? 1 : 0
  # ...
}

output "nat_gateway_id" {
  value = one(aws_nat_gateway.main[*].id)
  # Returns the ID if it exists, null if count = 0
  # Errors if the list has more than 1 item
}
```

---

## Step 3: Terraform Functions Deep Dive

Terraform has 100+ built-in functions. These are the ones you'll use every week.

### String functions
```hcl
locals {
  # format — like printf
  bucket_name = format("%s-%s-%s", var.project, var.environment, var.aws_region)
  # → "myapp-prod-us-east-1"

  # trimspace — remove leading/trailing whitespace
  clean_name = trimspace("  myapp  ")   # → "myapp"

  # replace — substitute substrings
  safe_name = replace(var.project, "_", "-")   # underscores → hyphens (S3 doesn't allow _)

  # split and join
  parts = split("-", "myapp-prod-us-east-1")
  # → ["myapp", "prod", "us", "east", "1"]
  rejoined = join("_", ["a", "b", "c"])   # → "a_b_c"

  # upper/lower
  env_upper = upper(var.environment)   # "PROD"
  env_lower = lower("DEV")             # "dev"

  # substr — extract part of a string
  short_region = substr(var.aws_region, 0, 6)   # "us-eas" from "us-east-1"
}
```

### Collection functions
```hcl
locals {
  azs = ["us-east-1a", "us-east-1b", "us-east-1c"]

  # length
  az_count = length(local.azs)   # → 3

  # contains
  has_1a = contains(local.azs, "us-east-1a")   # → true

  # distinct — remove duplicates
  unique_cidrs = distinct(["10.0.0.0/24", "10.0.0.0/24", "10.0.1.0/24"])
  # → ["10.0.0.0/24", "10.0.1.0/24"]

  # flatten — collapse nested lists
  nested = [["a", "b"], ["c", "d"]]
  flat   = flatten(local.nested)   # → ["a", "b", "c", "d"]

  # merge — combine maps (rightmost wins on conflict)
  base_tags  = { ManagedBy = "Terraform" }
  extra_tags = { Environment = "prod", ManagedBy = "Override" }
  all_tags   = merge(local.base_tags, local.extra_tags)
  # → { ManagedBy = "Override", Environment = "prod" }

  # keys and values
  tag_keys   = keys(local.all_tags)     # → ["Environment", "ManagedBy"]
  tag_values = values(local.all_tags)   # → ["prod", "Override"]

  # lookup — safe map access with default
  type = lookup(var.instance_types, var.environment, "t2.micro")
  # returns var.instance_types[var.environment], or "t2.micro" if key missing
}
```

### CIDR functions
```hcl
locals {
  vpc_cidr = "10.0.0.0/16"

  # cidrsubnet — calculate subnets from a parent CIDR
  # cidrsubnet(prefix, newbits, netnum)
  public_1  = cidrsubnet(local.vpc_cidr, 8, 1)   # → 10.0.1.0/24
  public_2  = cidrsubnet(local.vpc_cidr, 8, 2)   # → 10.0.2.0/24
  private_1 = cidrsubnet(local.vpc_cidr, 8, 11)  # → 10.0.11.0/24
  private_2 = cidrsubnet(local.vpc_cidr, 8, 12)  # → 10.0.12.0/24

  # Auto-generate all subnets in a loop
  public_subnets = [
    for i in range(2) : cidrsubnet(local.vpc_cidr, 8, i + 1)
  ]
  # → ["10.0.1.0/24", "10.0.2.0/24"]

  # cidrhost — get a specific IP from a CIDR
  first_ip = cidrhost("10.0.1.0/24", 1)   # → "10.0.1.1"
}
```

### Encoding functions
```hcl
locals {
  # base64encode — for EC2 user_data scripts
  user_data_b64 = base64encode(<<-EOT
    #!/bin/bash
    yum update -y
    yum install -y httpd
    echo "Hello from ${var.environment}" > /var/www/html/index.html
    systemctl start httpd
    systemctl enable httpd
  EOT
  )

  # jsonencode — convert HCL objects to JSON strings
  policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject"]
      Resource = "${aws_s3_bucket.data.arn}/*"
    }]
  })

  # yamldecode — parse YAML from a file
  config = yamldecode(file("${path.module}/config.yaml"))
}
```

---

### 📝 Assignment 3 (Advanced): Dynamic Security Group

**Task:** Replace all static security group ingress blocks with dynamic blocks.

1. Define a `list(object)` variable with at least 5 ingress rules (HTTP, HTTPS, SSH, 8080, custom)
2. Use a `dynamic "ingress"` block to generate all rules
3. Use `for` expressions to: extract all ports as a list, filter only TCP rules, convert to a map keyed by description
4. Add validation: no rule should allow port 22 from `0.0.0.0/0` (SSH to the world)

---

## Step 4: Security Hardening

Security is not an afterthought in Terraform — it's built into every resource you write.

### Principle of Least Privilege IAM

```hcl
# IAM role for EC2 — only the permissions it actually needs
resource "aws_iam_role" "app" {
  name = "${local.name_prefix}-app-role"

  # Trust policy — only EC2 can assume this role
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Permission policy — read one specific S3 bucket, nothing else
resource "aws_iam_policy" "app" {
  name = "${local.name_prefix}-app-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadAppBucket"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          aws_s3_bucket.app.arn,
          "${aws_s3_bucket.app.arn}/*"
        ]
      },
      {
        Sid    = "WriteLogging"
        Effect = "Allow"
        Action = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.logs.arn}/app-logs/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "app" {
  role       = aws_iam_role.app.name
  policy_arn = aws_iam_policy.app.arn
}

resource "aws_iam_instance_profile" "app" {
  name = "${local.name_prefix}-app-profile"
  role = aws_iam_role.app.name
}

# Attach to EC2
resource "aws_instance" "app" {
  iam_instance_profile = aws_iam_instance_profile.app.name
  # ... other config
}
```

### KMS encryption everywhere

```hcl
# Customer-managed KMS key
resource "aws_kms_key" "main" {
  description             = "Encryption key for ${var.project} ${var.environment}"
  deletion_window_in_days = 30
  enable_key_rotation     = true   # rotate annually — best practice

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      }
    ]
  })
}

resource "aws_kms_alias" "main" {
  name          = "alias/${var.project}-${var.environment}"
  target_key_id = aws_kms_key.main.key_id
}

# Encrypt S3 with KMS
resource "aws_s3_bucket_server_side_encryption_configuration" "app" {
  bucket = aws_s3_bucket.app.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.main.arn
    }
    bucket_key_enabled = true   # reduces KMS API call costs
  }
}

# Encrypt EBS with KMS
resource "aws_instance" "app" {
  root_block_device {
    volume_type = "gp3"
    encrypted   = true
    kms_key_id  = aws_kms_key.main.arn
  }
}

# Encrypt RDS with KMS
resource "aws_db_instance" "main" {
  storage_encrypted = true
  kms_key_id        = aws_kms_key.main.arn
}
```

### VPC Flow Logs

```hcl
resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/aws/vpc/flow-logs/${var.environment}"
  retention_in_days = 90   # legal minimum at many companies
  kms_key_id        = aws_kms_key.main.arn
}

resource "aws_iam_role" "vpc_flow_logs" {
  name               = "${local.name_prefix}-vpc-flow-logs-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_flow_log" "vpc" {
  vpc_id          = aws_vpc.main.id
  traffic_type    = "ALL"   # capture ACCEPT and REJECT
  iam_role_arn    = aws_iam_role.vpc_flow_logs.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_logs.arn
}
```

### Static security scanning with tfsec / checkov

Never merge code that hasn't been scanned. Add to your CI pipeline:

```yaml
# .github/workflows/security.yml

- name: Run tfsec
  uses: aquasecurity/tfsec-action@v1.0.3
  with:
    soft_fail: false   # fail the pipeline on HIGH severity findings

- name: Run Checkov
  uses: bridgecrewio/checkov-action@master
  with:
    directory: .
    framework: terraform
    soft_fail: false
    check: CKV_AWS_*   # run all AWS checks
```

**Common issues tfsec/checkov catch:**
- Security groups with `0.0.0.0/0` on SSH/RDP
- S3 buckets with public access
- Unencrypted EBS volumes, RDS instances
- Missing VPC Flow Logs
- IAM policies with `*` actions

---

## Step 5: Testing Terraform Code

Infrastructure code needs testing just like application code. There are three levels.

### Level 1 — Static validation (fastest, zero AWS calls)

```bash
# Syntax check
terraform validate

# Format check
terraform fmt -check -recursive

# Security scan
tfsec .
checkov -d .

# Lint with TFLint
tflint --recursive
```

### Level 2 — Terratest (integration tests in Go)

Terratest provisions real infrastructure, runs tests against it, then destroys it.

```go
// test/vpc_test.go
package test

import (
    "testing"
    "github.com/gruntwork-io/terratest/modules/terraform"
    "github.com/gruntwork-io/terratest/modules/aws"
    "github.com/stretchr/testify/assert"
)

func TestVPCModule(t *testing.T) {
    t.Parallel()

    terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
        TerraformDir: "../modules/vpc",
        Vars: map[string]interface{}{
            "project":     "test",
            "environment": "test",
            "vpc_cidr":    "10.99.0.0/16",
        },
    })

    // Always clean up — even if tests fail
    defer terraform.Destroy(t, terraformOptions)

    terraform.InitAndApply(t, terraformOptions)

    // Get the VPC ID from outputs
    vpcID := terraform.Output(t, terraformOptions, "vpc_id")

    // Verify the VPC exists in AWS
    vpc := aws.GetVpcById(t, vpcID, "us-east-1")
    assert.Equal(t, "10.99.0.0/16", aws.GetCidrBlock(vpc))

    // Verify subnets were created
    publicSubnetIDs := terraform.OutputList(t, terraformOptions, "public_subnet_ids")
    assert.Equal(t, 2, len(publicSubnetIDs))

    privateSubnetIDs := terraform.OutputList(t, terraformOptions, "private_subnet_ids")
    assert.Equal(t, 2, len(privateSubnetIDs))
}
```

```bash
cd test/
go test -v -timeout 30m ./...
```

### Level 3 — Native Terraform tests (v1.6+)

Terraform 1.6 introduced a built-in test framework — no Go required.

```hcl
# tests/vpc_basic.tftest.hcl

provider "aws" {
  region = "us-east-1"
}

variables {
  project     = "test"
  environment = "test"
  vpc_cidr    = "10.99.0.0/16"
}

run "vpc_is_created" {
  command = apply

  assert {
    condition     = aws_vpc.main.cidr_block == "10.99.0.0/16"
    error_message = "VPC CIDR block does not match"
  }

  assert {
    condition     = aws_vpc.main.enable_dns_hostnames == true
    error_message = "DNS hostnames should be enabled"
  }
}

run "subnets_are_created" {
  command = apply

  assert {
    condition     = length(aws_subnet.public) == 2
    error_message = "Expected 2 public subnets"
  }

  assert {
    condition     = length(aws_subnet.private) == 2
    error_message = "Expected 2 private subnets"
  }
}
```

```bash
terraform test
```

### Testing strategy in CI/CD

```
PR opened
    ↓
terraform validate + fmt       (< 10 seconds)
    ↓
tfsec + checkov                (< 30 seconds)
    ↓
terraform plan                 (< 2 minutes)
    ↓
PR reviewed and approved
    ↓
terraform test (native tests)  (5-15 minutes, creates real infra)
    ↓
terraform apply                (only on main)
```

---

## Step 6: Drift Detection & Remediation

**Drift** is when your real AWS infrastructure differs from what Terraform's state says it should be. Someone changed a security group rule manually in the Console. A tag was edited. An instance was stopped.

### Detecting drift

```bash
# terraform plan detects drift — any difference is shown as a change
terraform plan

# Refresh state from AWS (updates state to match real infra, then plan)
terraform refresh   # deprecated — use plan -refresh-only instead
terraform plan -refresh-only

# Apply the refresh (update state to match reality)
terraform apply -refresh-only
```

### Automated drift detection (scheduled pipeline)

```yaml
# .github/workflows/drift-detection.yml

name: Drift Detection

on:
  schedule:
    - cron: '0 6 * * 1-5'   # 6 AM UTC, weekdays

jobs:
  detect-drift:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id:     ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region:            us-east-1

      - uses: hashicorp/setup-terraform@v3

      - name: Terraform Init
        run: terraform init
        working-directory: environments/prod

      - name: Check for drift
        id: plan
        run: |
          terraform plan -refresh-only -detailed-exitcode -out=drift.tfplan
          echo "exit_code=$?" >> $GITHUB_OUTPUT
        working-directory: environments/prod
        continue-on-error: true

      - name: Alert on drift
        if: steps.plan.outputs.exit_code == '2'   # 2 = changes detected
        uses: slackapi/slack-github-action@v1
        with:
          payload: |
            {
              "text": "⚠️ Terraform drift detected in production! Review the plan and remediate.",
              "channel": "#infrastructure-alerts"
            }
        env:
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK }}
```

### `lifecycle` — protect critical resources

```hcl
resource "aws_db_instance" "main" {
  # ...

  lifecycle {
    # Prevent anyone from destroying this resource via terraform destroy
    prevent_destroy = true

    # Don't let Terraform modify these attributes in place (force manual approval)
    ignore_changes = [
      engine_version,       # handle RDS upgrades separately
      snapshot_identifier,  # don't recreate DB just because snapshot changed
    ]

    # Fail plan if these change (catch unintended modifications)
    precondition {
      condition     = var.environment == "prod" ? self.multi_az : true
      error_message = "Production RDS must have multi_az enabled."
    }
  }
}

resource "aws_autoscaling_group" "app" {
  # ...

  lifecycle {
    # Don't reset desired capacity when autoscaling changes it
    ignore_changes = [desired_capacity]

    # Create new ASG before destroying old one (zero-downtime replacement)
    create_before_destroy = true
  }
}
```

---

### 📝 Assignment 6 (Advanced): Security + Testing

**Task:** Harden an existing Terraform module and add tests.

1. Take your VPC module from Level 2 and add:
   - KMS key + encryption on all S3 buckets
   - VPC Flow Logs to CloudWatch
   - IAM role with least-privilege (S3 read only) for EC2
   - `lifecycle { prevent_destroy = true }` on VPC and S3
2. Run `tfsec` and `checkov` — resolve all HIGH severity findings
3. Write native Terraform tests (`tests/*.tftest.hcl`) verifying:
   - VPC CIDR is correct
   - 2 public and 2 private subnets exist
   - S3 bucket has versioning enabled
   - EC2 IAM role exists

---

## Step 7: Terragrunt — DRY at Scale

When you have 5+ environments across 3 AWS accounts with 20 modules, raw Terraform has too much repetition. Every environment needs the same backend config with only the key changing. Terragrunt solves this.

### The problem without Terragrunt

```hcl
# You copy this into EVERY environment — 20 environments = 20 copies
terraform {
  backend "s3" {
    bucket         = "mycompany-terraform-state"
    region         = "us-east-1"
    dynamodb_table = "mycompany-terraform-locks"
    encrypt        = true
    key            = "dev/vpc/terraform.tfstate"   # only this changes
  }
}
```

### Terragrunt structure

```
infrastructure/
├── terragrunt.hcl                    # root config — shared by all
├── dev/
│   ├── terragrunt.hcl                # dev-level config
│   ├── vpc/
│   │   └── terragrunt.hcl
│   ├── ec2/
│   │   └── terragrunt.hcl
│   └── rds/
│       └── terragrunt.hcl
└── prod/
    ├── terragrunt.hcl
    ├── vpc/
    │   └── terragrunt.hcl
    └── rds/
        └── terragrunt.hcl
```

**Root `terragrunt.hcl` — define backend once:**
```hcl
# infrastructure/terragrunt.hcl

locals {
  account_id  = get_aws_account_id()
  region      = "us-east-1"
  environment = basename(dirname(get_terragrunt_dir()))
}

# Generate backend.tf automatically for every module
remote_state {
  backend = "s3"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite"
  }
  config = {
    bucket         = "mycompany-terraform-state-${local.account_id}"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = local.region
    dynamodb_table = "mycompany-terraform-locks"
    encrypt        = true
  }
}
```

**Module-level `terragrunt.hcl`:**
```hcl
# infrastructure/dev/vpc/terragrunt.hcl

# Pull in root config
include "root" {
  path = find_in_parent_folders()
}

# Point to the module to use
terraform {
  source = "../../../modules//vpc"
}

# Pass inputs to the module
inputs = {
  project             = "myapp"
  environment         = "dev"
  vpc_cidr            = "10.0.0.0/16"
  enable_nat_gateway  = false
}
```

**Deploy one module:**
```bash
cd infrastructure/dev/vpc
terragrunt apply
```

**Deploy all dev infrastructure at once:**
```bash
cd infrastructure/dev
terragrunt run-all apply   # applies vpc, ec2, rds in dependency order
```

### Module dependencies in Terragrunt

```hcl
# infrastructure/dev/ec2/terragrunt.hcl

include "root" { path = find_in_parent_folders() }

terraform { source = "../../../modules//ec2" }

# Declare dependency on VPC — EC2 needs VPC to exist first
dependency "vpc" {
  config_path = "../vpc"
}

inputs = {
  vpc_id            = dependency.vpc.outputs.vpc_id
  private_subnet_ids = dependency.vpc.outputs.private_subnet_ids
  environment       = "dev"
}
```

Terragrunt automatically:
- Creates VPC before EC2
- Passes VPC outputs as EC2 inputs
- Destroys EC2 before VPC on `run-all destroy`

---

## Step 8: Managing Secrets

Secrets are the most common security failure in Terraform projects. Here are the safe patterns.

### AWS Secrets Manager

```hcl
# Store a secret
resource "aws_secretsmanager_secret" "db_password" {
  name                    = "/${var.project}/${var.environment}/db/password"
  recovery_window_in_days = 30
  kms_key_id              = aws_kms_key.main.arn
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = var.db_password   # passed in via TF_VAR, never in code
}

# Read a secret (for injecting into other resources)
data "aws_secretsmanager_secret_version" "api_key" {
  secret_id = "/${var.project}/${var.environment}/api/key"
}

locals {
  api_key = data.aws_secretsmanager_secret_version.api_key.secret_string
}
```

### AWS SSM Parameter Store

```hcl
# Store a parameter
resource "aws_ssm_parameter" "db_host" {
  name   = "/${var.project}/${var.environment}/db/host"
  type   = "String"
  value  = aws_db_instance.main.endpoint
}

resource "aws_ssm_parameter" "db_password" {
  name   = "/${var.project}/${var.environment}/db/password"
  type   = "SecureString"           # encrypted with KMS
  value  = var.db_password
  key_id = aws_kms_key.main.arn
}

# Read a parameter
data "aws_ssm_parameter" "db_password" {
  name            = "/${var.project}/${var.environment}/db/password"
  with_decryption = true
}
```

### The Secrets Anti-patterns — Never Do These

```hcl
# ❌ NEVER: hardcoded secret in variable default
variable "db_password" {
  default = "MySuperSecretP@ssw0rd"   # visible in Git history forever
}

# ❌ NEVER: secret in a tag
resource "aws_instance" "app" {
  tags = { DBPassword = "mysecret" }  # stored in state, visible in Console
}

# ❌ NEVER: secret in user_data inline
resource "aws_instance" "app" {
  user_data = "echo DB_PASS=mysecret >> /etc/environment"  # in state file
}

# ✅ CORRECT: pass via environment variable, read from Secrets Manager at runtime
resource "aws_instance" "app" {
  user_data = <<-EOT
    #!/bin/bash
    DB_PASS=$(aws secretsmanager get-secret-value \
      --secret-id /${var.project}/${var.environment}/db/password \
      --query SecretString --output text)
    echo "DB_PASS=$DB_PASS" >> /etc/environment
  EOT
}
```

---

## Step 9: Enterprise Patterns

### Multi-account architecture with AWS Organizations

```
AWS Organization
├── Management Account       (billing, SCPs)
├── Security Account         (CloudTrail, SecurityHub, GuardDuty)
├── Shared Services Account  (ECR, shared AMIs, Transit Gateway)
├── Dev Account
├── Staging Account
└── Prod Account
```

```hcl
# Deploy to multiple accounts using provider aliasing
provider "aws" {
  alias  = "dev"
  region = "us-east-1"
  assume_role {
    role_arn = "arn:aws:iam::111111111111:role/TerraformDeployRole"
  }
}

provider "aws" {
  alias  = "prod"
  region = "us-east-1"
  assume_role {
    role_arn = "arn:aws:iam::222222222222:role/TerraformDeployRole"
  }
}

# Deploy VPC to dev account
module "vpc_dev" {
  source    = "./modules/vpc"
  providers = { aws = aws.dev }
  environment = "dev"
}

# Deploy VPC to prod account
module "vpc_prod" {
  source    = "./modules/vpc"
  providers = { aws = aws.prod }
  environment = "prod"
}
```

### Versioned module registry with semantic versioning

```hcl
# Reference a specific version of a module from GitHub
module "vpc" {
  source = "git::https://github.com/mycompany/terraform-modules.git//modules/vpc?ref=v2.1.0"

  project     = var.project
  environment = var.environment
}
```

Tagging convention for modules:
```bash
git tag v2.1.0
git push origin v2.1.0
```

### `moved` block — rename resources without destroying

When you rename a resource in code, Terraform wants to destroy the old one and create a new one. The `moved` block prevents this:

```hcl
# You renamed aws_instance.app to aws_instance.web_server
# Without moved block: destroy app, create web_server (downtime!)
# With moved block: just update state (no AWS changes)

moved {
  from = aws_instance.app
  to   = aws_instance.web_server
}

# Also works for moving resources into a module
moved {
  from = aws_instance.web_server
  to   = module.ec2.aws_instance.web_server
}
```

### `import` block (Terraform 1.5+) — adopt existing infrastructure

```hcl
# Generate Terraform code for an existing resource
import {
  id = "i-0abc123def456789"   # existing EC2 instance ID
  to = aws_instance.web
}
```

```bash
# Generate the resource config automatically
terraform plan -generate-config-out=generated.tf

# Review generated.tf, adjust as needed, then apply
terraform apply
```

### `check` blocks — continuous assertions

```hcl
# Assert conditions on every plan/apply — like smoke tests baked into Terraform
check "s3_bucket_is_private" {
  data "aws_s3_bucket" "app" {
    bucket = aws_s3_bucket.app.bucket
  }

  assert {
    condition     = data.aws_s3_bucket.app.bucket_acl == null
    error_message = "S3 bucket ${aws_s3_bucket.app.bucket} has a public ACL — fix immediately."
  }
}

check "rds_is_encrypted" {
  assert {
    condition     = aws_db_instance.main.storage_encrypted == true
    error_message = "RDS instance must be encrypted at rest."
  }
}
```

---

## Level 3 Final Assignment

> **This is your Capstone Project. It represents production-grade work. Full code review required.**

### The Scenario
Your company is scaling to multiple environments (dev, staging, prod) and needs an enterprise-grade Terraform codebase. You are the lead infrastructure engineer. Build it.

### Requirements

**Part A — Architecture (20 points)**

Provision the following in `dev` and `prod` environments using modules:

1. VPC with 2 AZs (public + private subnets each), Flow Logs enabled
2. Application Load Balancer in public subnets
3. Auto Scaling Group (2–6 instances) behind the ALB in private subnets
4. RDS PostgreSQL (single-AZ in dev, multi-AZ in prod) in private subnets
5. S3 bucket for application assets

All resources must use your KMS key for encryption.

**Part B — Terragrunt (20 points)**
1. Implement Terragrunt with a root `terragrunt.hcl` that generates backend config
2. Each module directory has its own `terragrunt.hcl` with `dependency` blocks
3. `terragrunt run-all plan` on the `dev` folder completes with zero errors
4. RDS depends on VPC, EC2/ASG depends on VPC + Security Group

**Part C — Security (20 points)**
1. All EC2 instances use IAM roles (no hardcoded credentials anywhere)
2. RDS password stored in AWS Secrets Manager, never in code or state
3. Security groups follow least-privilege (no `0.0.0.0/0` on port 22)
4. `tfsec` and `checkov` pass with zero HIGH severity findings
5. KMS encryption on: EBS, RDS, S3, CloudWatch Logs, Secrets Manager

**Part D — Testing (20 points)**
1. Native Terraform tests for VPC module: CIDR, subnet count, DNS settings
2. Native Terraform tests for Security Group module: verify no port 22 from internet
3. CI pipeline runs tests automatically on every PR
4. Drift detection pipeline runs daily and alerts to Slack on changes

**Part E — Operations (20 points)**
1. `moved` block used to rename at least one resource without recreation
2. `lifecycle { prevent_destroy = true }` on RDS and S3
3. `check` blocks asserting S3 is private and RDS is encrypted
4. `terraform apply` uses saved plan files (`-out=tfplan`)
5. Outputs expose: ALB DNS name, RDS endpoint (sensitive), ASG name, all subnet IDs

### Submission Requirements
- [ ] Code in private GitHub repo with branch protection on `main`
- [ ] All CI checks green on a test PR
- [ ] `terragrunt run-all plan` output for `dev` — zero errors, shared with tutor
- [ ] `tfsec` and `checkov` output — zero HIGH findings
- [ ] Terraform test results showing all tests pass
- [ ] `terraform apply` completed for `dev` — ALB DNS resolves
- [ ] Written `ARCHITECTURE.md` explaining your design decisions (min. 500 words)

### Grading
| Score | Outcome |
|---|---|
| 90–100 | You're ready to work as a junior DevOps engineer on infrastructure teams |
| 75–89 | Strong work — address feedback and you're production-ready |
| Below 75 | Review flagged sections, re-submit with improvements |

---

## The Complete Skills Matrix

After completing all three levels, you should be able to:

| Skill | Level |
|---|---|
| Write and apply basic Terraform resources | ✅ Basic |
| Use variables, outputs, and state | ✅ Basic |
| Configure remote state with S3 + DynamoDB | ✅ Intermediate |
| Write and call reusable modules | ✅ Intermediate |
| Build VPC + subnets from scratch | ✅ Intermediate |
| Use `count` and `for_each` for loops | ✅ Intermediate |
| Set up CI/CD with GitHub Actions | ✅ Intermediate |
| Write dynamic blocks and for expressions | ✅ Advanced |
| Enforce IAM least privilege via Terraform | ✅ Advanced |
| Run tfsec/checkov and fix findings | ✅ Advanced |
| Write and run native Terraform tests | ✅ Advanced |
| Implement Terragrunt for multi-env DRY | ✅ Advanced |
| Manage secrets with Secrets Manager | ✅ Advanced |
| Detect and remediate configuration drift | ✅ Advanced |
| Work with multi-account AWS Organizations | ✅ Advanced |

---

## Recommended Next Steps

1. **HashiCorp Certified: Terraform Associate** — take this exam within 30 days of finishing Level 3
2. **AWS Solutions Architect Associate** — pairs perfectly with your new Terraform knowledge
3. **Explore:** Atlantis (self-hosted Terraform CI/CD), OpenTofu (open-source Terraform fork), Pulumi (IaC in Python/TypeScript)
4. **Read:** "Terraform: Up & Running" by Yevgeniy Brikman — the definitive book on production Terraform

---

*Previous: [Level 2 — Intermediate](./README-intermediate.md)*  
*Start over: [Level 1 — Basic](./README-basic.md)*