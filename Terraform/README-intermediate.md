# Terraform Training — Level 2: Intermediate
> **Prerequisites:** Level 1 complete + final assignment passed  
> **Goal:** Build real team-grade infrastructure with modules, remote state, VPCs, and CI/CD  
> **Time estimate:** 3–4 days  

---

## What Changes at This Level

In Level 1, you worked alone on simple resources. At this level:
- Your code is shared with a team (remote state + locking)
- Infrastructure gets more complex (full VPC, subnets, routing)
- You stop repeating yourself (modules)
- Multiple environments (dev/staging/prod) run from the same codebase
- Code is reviewed before it reaches AWS (CI/CD pipeline)

---

## Table of Contents
1. [Remote State with S3 + DynamoDB](#step-1-remote-state-with-s3--dynamodb)
2. [Data Sources](#step-2-data-sources)
3. [Local Values](#step-3-local-values)
4. [count and for_each](#step-4-count-and-for_each)
5. [VPC, Subnets & Routing](#step-5-vpc-subnets--routing)
6. [Modules — Writing Your Own](#step-6-modules--writing-your-own)
7. [Modules — Using Public Registry](#step-7-modules--using-public-registry)
8. [Workspaces & Multi-Environment Strategy](#step-8-workspaces--multi-environment-strategy)
9. [Terraform with CI/CD (GitHub Actions)](#step-9-terraform-with-cicd-github-actions)
10. [Level 2 Final Assignment](#level-2-final-assignment)

---

## Step 1: Remote State with S3 + DynamoDB

### The problem with local state on a team

When your teammate runs `terraform apply` at the same time as you, both writes hit the same state file simultaneously — corrupting it. Local state also lives on your laptop, so if you're on vacation, no one can make changes.

Remote state solves both problems: state lives in S3 (shared, durable), and DynamoDB provides a lock (only one apply runs at a time).

### The Bootstrap Pattern

This is the chicken-and-egg problem: you need Terraform to create the S3 bucket for state, but you need the bucket before you can use remote state. The solution is a one-time bootstrap.

**Step 1: Create the bootstrap resources (run once, ever)**

```
bootstrap/
├── main.tf
└── outputs.tf
```

```hcl
# bootstrap/main.tf

provider "aws" {
  region = "us-east-1"
}

resource "aws_s3_bucket" "terraform_state" {
  bucket = "mycompany-terraform-state"   # unique name for your company

  # CRITICAL: prevent accidental deletion of your entire state history
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name      = "Terraform State"
    ManagedBy = "Terraform Bootstrap"
  }
}

# Block all public access — state can contain secrets
resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Encrypt at rest
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Keep every historical version — your safety net for accidental deletions
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration { status = "Enabled" }
}

# DynamoDB table for state locking
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "mycompany-terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"  # Terraform requires exactly this key name

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = { Name = "Terraform State Locks" }
}
```

```bash
cd bootstrap/
terraform init    # uses local state — this is intentional
terraform apply
```

**Step 2: Configure backend in your main project**

```hcl
# backend.tf  (in your main project, NOT bootstrap)

terraform {
  backend "s3" {
    bucket         = "mycompany-terraform-state"
    key            = "dev/terraform.tfstate"     # path inside the bucket
    region         = "us-east-1"
    dynamodb_table = "mycompany-terraform-locks"
    encrypt        = true
  }
}
```

```bash
terraform init   # Terraform asks: "Migrate existing state?" → type yes
```

### Multi-environment state layout
```
mycompany-terraform-state/   (S3 bucket)
├── global/terraform.tfstate      ← shared IAM, Route53, certificates
├── dev/terraform.tfstate
├── staging/terraform.tfstate
└── prod/terraform.tfstate
```

### Recovering from a stuck lock

If `terraform apply` crashes mid-run, the DynamoDB lock stays:
```bash
# Get the lock ID from the error message, then:
terraform force-unlock <LOCK_ID>
```

> ⚠️ Only force-unlock if you are 100% certain no apply is running. Check with your team first.

---

### 📝 Assignment 1 (Intermediate): Remote State Setup

**Task:** Migrate your Level 1 project to remote state.

1. Create the bootstrap project and apply it
2. Add `backend.tf` to your Level 1 project
3. Run `terraform init` and migrate state to S3
4. Verify the state file appears in S3 Console
5. Run `terraform plan` — it should work with no changes

**Questions:**
- What is inside the DynamoDB table when an apply is running?
- What happens if you delete the S3 bucket while state is stored there?

---

## Step 2: Data Sources

A **data source** reads existing AWS resources without creating or managing them. Use it when you need info about something Terraform didn't create — like an existing VPC, the latest AMI ID, or your AWS account number.

```hcl
# Get the latest Amazon Linux 2 AMI — no more hardcoding AMI IDs
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# Use it in a resource
resource "aws_instance" "web" {
  ami           = data.aws_ami.amazon_linux.id   # always up-to-date
  instance_type = "t2.micro"
}

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

output "account_id" {
  value = data.aws_caller_identity.current.account_id
}

# Look up an existing VPC by tag (created outside Terraform)
data "aws_vpc" "existing" {
  filter {
    name   = "tag:Name"
    values = ["production-vpc"]
  }
}

# Look up existing subnets inside that VPC
data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.existing.id]
  }
  filter {
    name   = "tag:Type"
    values = ["private"]
  }
}
```

**When to use data sources vs resources:**
| Use `resource` when... | Use `data` when... |
|---|---|
| Terraform should create and manage it | It already exists outside Terraform |
| You want Terraform to own its lifecycle | You just need to read its attributes |
| Example: new EC2 instance | Example: existing VPC, latest AMI |

---

## Step 3: Local Values

**Locals** are computed internal values — not inputs from outside, just values you calculate inside your configuration to avoid repetition.

```hcl
# locals.tf

locals {
  # Build a name prefix used in every resource name
  name_prefix = "${var.project}-${var.environment}"

  # Common tags merged onto every resource — define once, use everywhere
  common_tags = merge(var.extra_tags, {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "Terraform"
    Owner       = "platform-team"
    CostCenter  = var.cost_center
  })

  # Compute AZ count from the list
  az_count = length(var.availability_zones)

  # Conditional: only use NAT in non-dev environments
  use_nat_gateway = var.environment != "dev"

  # Build a map from a list (useful for for_each)
  subnet_map = {
    for idx, cidr in var.private_subnet_cidrs :
    "private-${idx + 1}" => cidr
  }
}

# Use locals with local.<n>
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  tags       = merge(local.common_tags, { Name = "${local.name_prefix}-vpc" })
}
```

**Variables vs Locals vs Outputs:**
| | Variables | Locals | Outputs |
|---|---|---|---|
| Direction | Input (from outside) | Internal | Output (to outside) |
| Who sets them | User / CI | You in code | Terraform after apply |
| Use for | Config values | Computed values | Exposing results |

---

## Step 4: count and for_each

### `count` — create N copies of a resource

```hcl
# Create 3 EC2 instances
resource "aws_instance" "app" {
  count         = var.instance_count     # e.g. 3
  ami           = data.aws_ami.al2.id
  instance_type = var.instance_type

  tags = {
    Name  = "${var.environment}-app-${count.index + 1}"  # app-1, app-2, app-3
    Index = count.index
  }
}

# Reference a specific instance
output "first_instance_ip" {
  value = aws_instance.app[0].public_ip
}

# Reference all instances
output "all_ips" {
  value = aws_instance.app[*].public_ip
}

# Toggle a resource on/off with bool
resource "aws_nat_gateway" "main" {
  count         = var.enable_nat_gateway ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public[0].id
}
```

### `for_each` — create one resource per map/set item (preferred for named resources)

```hcl
# Create multiple S3 buckets from a map
variable "buckets" {
  default = {
    assets  = "myapp-assets-2024"
    backups = "myapp-backups-2024"
    logs    = "myapp-logs-2024"
  }
}

resource "aws_s3_bucket" "buckets" {
  for_each = var.buckets

  bucket = each.value   # the map value
  tags   = { Name = each.key }  # the map key: "assets", "backups", "logs"
}

# Create security group rules from a list of objects
variable "ingress_rules" {
  default = [
    { port = 80,  protocol = "tcp", description = "HTTP"  },
    { port = 443, protocol = "tcp", description = "HTTPS" },
  ]
}

resource "aws_security_group_rule" "ingress" {
  for_each = { for rule in var.ingress_rules : rule.port => rule }

  type        = "ingress"
  from_port   = each.value.port
  to_port     = each.value.port
  protocol    = each.value.protocol
  description = each.value.description
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = aws_security_group.web.id
}
```

### count vs for_each — when to use which

| `count` | `for_each` |
|---|---|
| Create N identical resources | Create resources with distinct identities |
| Toggle a resource on/off | Create resources from a list/map |
| Resources tracked as `resource[0]`, `[1]` | Resources tracked as `resource["key"]` |
| Removing index 0 forces recreation of all | Removing a key only affects that resource |
| Simple, good for homogeneous resources | Better for named, heterogeneous resources |

> **Best practice:** Prefer `for_each` over `count` whenever the resources have meaningful names. Removing `count[0]` renumbers everything and forces unnecessary recreation.

---

### 📝 Assignment 4 (Intermediate): Loops Practice

**Task:** Provision multiple resources using both `count` and `for_each`.

1. Use `for_each` to create 3 S3 buckets: `dev-assets`, `dev-backups`, `dev-logs`
2. Use `count` to create 2 EC2 instances
3. Output all bucket ARNs as a list using `values(aws_s3_bucket.buckets)[*].arn`
4. Output all EC2 public IPs using `aws_instance.app[*].public_ip`
5. **Challenge:** Add one more bucket to `for_each` and run `terraform plan`. Observe that only 1 resource is added. Then use `count` with a list and remove index 0 — observe how it forces recreation.

---

## Step 5: VPC, Subnets & Routing

This is the most important networking pattern in AWS. Every production app needs it.

### Architecture
```
Internet
    |
Internet Gateway (IGW)
    |
+---VPC (10.0.0.0/16)-------------------+
|                                        |
|  AZ us-east-1a        AZ us-east-1b  |
|  +--Public Subnet--+  +--Public--+   |
|  | 10.0.1.0/24     |  |10.0.2.0  |   |
|  | ALB, NAT GW     |  |ALB       |   |
|  +--------+--------+  +----+-----+   |
|           |                |          |
|  +--Private Subnet-+  +--Private-+   |
|  | 10.0.3.0/24     |  |10.0.4.0  |   |
|  | EC2, RDS, ECS   |  |EC2, RDS  |   |
|  +-----------------+  +----------+   |
+----------------------------------------+
```

**Full VPC module code:**

```hcl
# vpc/main.tf

# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = merge(local.common_tags, { Name = "${local.name_prefix}-vpc" })
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = merge(local.common_tags, { Name = "${local.name_prefix}-igw" })
}

# Public Subnets — one per AZ
resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true   # EC2 here gets a public IP

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-public-${count.index + 1}"
    Type = "public"
  })
}

# Private Subnets — one per AZ
resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-private-${count.index + 1}"
    Type = "private"
  })
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat" {
  count  = local.use_nat_gateway ? 1 : 0
  domain = "vpc"
  tags   = merge(local.common_tags, { Name = "${local.name_prefix}-nat-eip" })
}

# NAT Gateway — in first public subnet, serves private subnets
resource "aws_nat_gateway" "main" {
  count         = local.use_nat_gateway ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public[0].id
  depends_on    = [aws_internet_gateway.main]
  tags          = merge(local.common_tags, { Name = "${local.name_prefix}-nat" })
}

# Public Route Table: all traffic → IGW
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = merge(local.common_tags, { Name = "${local.name_prefix}-public-rt" })
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private Route Table: all traffic → NAT Gateway (if enabled)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  dynamic "route" {
    for_each = local.use_nat_gateway ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.main[0].id
    }
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-private-rt" })
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
```

---

## Step 6: Modules — Writing Your Own

A **module** is a reusable package of Terraform resources — like a function in code. Once written, you call it multiple times with different inputs.

### Module structure
```
modules/
└── vpc/
    ├── main.tf       # resources
    ├── variables.tf  # inputs
    ├── outputs.tf    # outputs
    └── README.md     # document your module!
```

### Writing a module

**`modules/vpc/variables.tf`:**
```hcl
variable "project"     { type = string }
variable "environment" { type = string }
variable "vpc_cidr"    { type = string; default = "10.0.0.0/16" }

variable "availability_zones" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "enable_nat_gateway" {
  type    = bool
  default = false
}
```

**`modules/vpc/outputs.tf`:**
```hcl
output "vpc_id"             { value = aws_vpc.main.id }
output "public_subnet_ids"  { value = aws_subnet.public[*].id }
output "private_subnet_ids" { value = aws_subnet.private[*].id }
output "vpc_cidr"           { value = aws_vpc.main.cidr_block }
```

### Calling your module

```hcl
# main.tf (root project)

module "vpc_dev" {
  source = "./modules/vpc"   # local path

  project     = "myapp"
  environment = "dev"
  vpc_cidr    = "10.0.0.0/16"
  enable_nat_gateway = false   # save money in dev
}

module "vpc_prod" {
  source = "./modules/vpc"   # same module, different inputs

  project     = "myapp"
  environment = "prod"
  vpc_cidr    = "10.1.0.0/16"
  enable_nat_gateway = true   # required in prod
}

# Access module outputs
resource "aws_instance" "app" {
  subnet_id = module.vpc_dev.private_subnet_ids[0]
}
```

```bash
# Modules require re-init when first added
terraform init
terraform plan
```

### Module best practices
1. **Always write a `README.md`** for your module — document every input and output
2. **Never put provider configuration inside a module** — let the caller configure providers
3. **Version your modules** — use Git tags and reference them: `source = "git::https://github.com/myorg/terraform-modules.git//vpc?ref=v1.2.0"`
4. **Keep modules focused** — one module does one thing (VPC module, not "everything module")
5. **Test your modules** — apply them in a sandbox before sharing with the team

---

### 📝 Assignment 6 (Intermediate): Build a Reusable Module

**Task:** Extract the VPC from Step 5 into a reusable module.

1. Create `modules/vpc/` with `main.tf`, `variables.tf`, `outputs.tf`, `README.md`
2. Call the module twice from root: once for `dev`, once for `staging` with different CIDRs
3. Deploy an EC2 instance using the `private_subnet_ids` output from the `dev` module
4. In `README.md` document: purpose, all inputs (with types + defaults), all outputs, usage example

---

## Step 7: Modules — Using Public Registry

The [Terraform Registry](https://registry.terraform.io) has thousands of community modules. Always evaluate before using — check downloads, last update date, and open issues.

```hcl
# Use the official AWS VPC module (battle-tested, 50M+ downloads)
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.2"   # always pin the version

  name = "myapp-prod-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway     = true
  single_nat_gateway     = false  # one per AZ for high availability
  enable_dns_hostnames   = true

  tags = local.common_tags
}

# Outputs from the registry module
output "vpc_id"             { value = module.vpc.vpc_id }
output "private_subnet_ids" { value = module.vpc.private_subnets }
```

> **When to use registry modules vs writing your own:**
> - Registry: standard AWS services with well-known configuration (VPC, EKS, RDS)
> - Write your own: company-specific patterns, internal standards enforcement, non-standard combinations

---

## Step 8: Workspaces & Multi-Environment Strategy

### Terraform Workspaces (simple approach)

Workspaces let you maintain separate state files for different environments using the same code.

```bash
# Create and switch to a workspace
terraform workspace new dev
terraform workspace new staging
terraform workspace new prod

# List workspaces
terraform workspace list

# Switch workspace
terraform workspace select prod

# Current workspace name is available in code
terraform workspace show   # → prod
```

Use workspace name in your code:
```hcl
locals {
  env    = terraform.workspace          # "dev", "staging", "prod"
  is_prod = terraform.workspace == "prod"
}

resource "aws_instance" "app" {
  instance_type = local.is_prod ? "t3.large" : "t2.micro"
  count         = local.is_prod ? 3 : 1
}
```

### Directory-based multi-env (recommended for large teams)

For complex projects, many teams prefer separate directories over workspaces:

```
environments/
├── dev/
│   ├── main.tf
│   ├── backend.tf       # key = "dev/terraform.tfstate"
│   └── terraform.tfvars
├── staging/
│   ├── main.tf
│   ├── backend.tf       # key = "staging/terraform.tfstate"
│   └── terraform.tfvars
└── prod/
    ├── main.tf
    ├── backend.tf       # key = "prod/terraform.tfstate"
    └── terraform.tfvars
```

Each environment calls the same modules but with different `tfvars`:
```hcl
# environments/prod/main.tf
module "vpc" {
  source             = "../../modules/vpc"
  environment        = "prod"
  vpc_cidr           = "10.2.0.0/16"
  enable_nat_gateway = true
}
```

---

## Step 9: Terraform with CI/CD (GitHub Actions)

Manual `terraform apply` is risky. A CI/CD pipeline enforces review: every change goes through `plan` first, and `apply` only runs after human approval on the main branch.

### Repository structure
```
.
├── .github/
│   └── workflows/
│       └── terraform.yml
├── environments/
│   ├── dev/
│   └── prod/
├── modules/
│   └── vpc/
└── README.md
```

### GitHub Actions workflow

```yaml
# .github/workflows/terraform.yml

name: Terraform

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

env:
  TF_VERSION: "1.7.0"
  AWS_REGION: "us-east-1"

jobs:
  terraform:
    name: Plan & Apply
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: environments/dev

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id:     ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region:            ${{ env.AWS_REGION }}

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      - name: Terraform Format Check
        run: terraform fmt -check -recursive
        # Fails the pipeline if code isn't formatted

      - name: Terraform Init
        run: terraform init

      - name: Terraform Validate
        run: terraform validate

      - name: Terraform Plan
        run: terraform plan -out=tfplan
        # On PRs: plan shows what will change
        # Reviewer sees this in the PR before approving

      - name: Terraform Apply
        # Only apply on pushes to main (after PR is merged)
        if: github.ref == 'refs/heads/main' && github.event_name == 'push'
        run: terraform apply tfplan
```

### Security: GitHub Secrets needed
```
AWS_ACCESS_KEY_ID     → your AWS access key
AWS_SECRET_ACCESS_KEY → your AWS secret key
```

> **Best practice:** Use an IAM user with only the permissions needed for Terraform. Not your personal admin credentials.

---

## Level 2 Final Assignment

> **This is your capstone project for the Intermediate level. Code review required before Level 3.**

### The Scenario
Your startup is growing. You need to provision a complete, team-ready development environment on AWS using Terraform best practices. Everything must be automated, modular, and safe for a team to use.

### Requirements

**Part A — Remote State (20 points)**
1. Bootstrap S3 bucket + DynamoDB table
2. All environment state files use remote state
3. Versioning and encryption enabled on the state bucket
4. `.gitignore` excludes all state files and `.terraform/` directories

**Part B — VPC Module (25 points)**
1. Write a `modules/vpc/` module with: VPC, public subnets (x2 AZs), private subnets (x2 AZs), IGW, NAT Gateway (toggleable via bool), route tables, associations
2. Module has full `variables.tf` with descriptions and types, `outputs.tf` exposing VPC ID + subnet IDs, and a `README.md`
3. Call the module for a `dev` environment (no NAT) and a `staging` environment (with NAT)

**Part C — Application Layer (25 points)**
1. Using the VPC module outputs, deploy in the `dev` environment:
   - A Security Group (HTTP 80/443 from internet, SSH from your IP only)
   - 2 EC2 instances in private subnets (use `count`) running Amazon Linux 2
   - 1 Application Load Balancer in public subnets forwarding to the EC2 instances
2. Use `data "aws_ami"` — no hardcoded AMI IDs

**Part D — Variables, Locals & Outputs (15 points)**
1. All environments use separate `.tfvars` files
2. A `locals` block defines `common_tags` used on every resource
3. Outputs expose: VPC ID, subnet IDs, ALB DNS name, EC2 instance IDs

**Part E — CI/CD (15 points)**
1. GitHub Actions pipeline runs `fmt`, `validate`, `plan` on every PR
2. `apply` runs only on merge to `main`
3. AWS credentials stored as GitHub Secrets, never in code

### Submission Requirements
- [ ] All code in a private GitHub repo
- [ ] `terraform plan` output for `dev` environment shared with tutor (0 errors)
- [ ] Pipeline screenshot showing green `plan` on a test PR
- [ ] `terraform apply` completed for `dev` — ALB DNS name resolves (even if it shows 503)
- [ ] `terraform destroy` on `dev` completes cleanly

### Grading
| Score | Outcome |
|---|---|
| 90–100 | Excellent — ready for Level 3 |
| 70–89 | Good — address review comments, then proceed |
| Below 70 | Review Modules + VPC steps, redo relevant parts |

---

## Key Takeaways from Level 2

- Remote state is not optional for teams — set it up before writing any other code
- Modules are how you enforce standards and stop copy-paste infrastructure
- `for_each` is almost always better than `count` for named resources
- Data sources bridge the gap between Terraform-managed and manually-created resources
- CI/CD makes infrastructure changes as reviewed and auditable as application code
- Never apply directly from your laptop in shared environments — use the pipeline

---

*Previous: [Level 1 — Basic](./README-basic.md)*  
*Next: [Level 3 — Advanced](./README-advanced.md) — Terragrunt, testing, security scanning, drift detection, and enterprise patterns*
