# Terraform Training — Level 1: Basic
> **Audience:** DevOps intern with AWS Console experience  
> **Goal:** Understand Terraform core concepts and provision real AWS infrastructure from code  
> **Time estimate:** 2–3 days  

---

## Before You Begin

### What You Already Know (AWS Console)
You can create EC2 instances, SSH into them, and create S3 buckets manually. That's great. But imagine doing that for 50 servers across 3 environments, every week. Terraform lets you do all of that with a single command — and undo it just as fast.

### What You Will Know After This Level
- What Infrastructure as Code (IaC) is and why it matters
- How to install and configure Terraform
- What providers, resources, state, variables, and outputs are
- How to create real AWS resources (S3, EC2, Security Groups)
- The core Terraform workflow: `init → plan → apply → destroy`

---

## Table of Contents
1. [What is Terraform?](#step-1-what-is-terraform)
2. [Installation & AWS Setup](#step-2-installation--aws-setup)
3. [Your First Terraform File](#step-3-your-first-terraform-file)
4. [Providers](#step-4-providers)
5. [Resources](#step-5-resources)
6. [Terraform Workflow](#step-6-terraform-workflow)
7. [State](#step-7-state)
8. [Variables](#step-8-variables)
9. [Outputs](#step-9-outputs)
10. [Level 1 Final Assignment](#level-1-final-assignment)

---

## Step 1: What is Terraform?

Terraform is an **Infrastructure as Code (IaC)** tool made by HashiCorp. Instead of clicking around the AWS Console to create infrastructure, you write code that describes what you want — and Terraform creates it for you.

### Why does this matter?

| AWS Console (Manual) | Terraform (IaC) |
|---|---|
| Click buttons to create resources | Write code, run one command |
| Easy to make mistakes | Reviewed like code, less error-prone |
| Hard to reproduce exactly | Run the same code = exact same infra |
| No history of what changed | Git tracks every change |
| Teardown is slow and manual | `terraform destroy` removes everything |
| Doesn't scale beyond a few servers | Manages thousands of resources |

### The core idea
You write `.tf` files describing your desired infrastructure. Terraform reads them, figures out what needs to be created/changed/deleted, and does it — talking directly to the AWS API.

```
Your .tf files  →  terraform plan  →  terraform apply  →  AWS Resources
```

### Real-world analogy
Think of Terraform like a restaurant order form. You write down exactly what you want (infrastructure). The waiter (Terraform) takes your order to the kitchen (AWS API) and brings back exactly what you ordered. Next time, hand them the same form and you get the same meal — every time.

---

## Step 2: Installation & AWS Setup

### 2.1 Install Terraform

**macOS (Homebrew):**
```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
```

**Windows (Chocolatey):**
```bash
choco install terraform
```

**Linux (Ubuntu/Debian):**
```bash
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform
```

**Verify:**
```bash
terraform version
# Expected output: Terraform v1.7.x
```

### 2.2 Install AWS CLI
```bash
# macOS
brew install awscli

# Verify
aws --version
```

### 2.3 Configure AWS Credentials

> ⚠️ **Security Rule #1:** Never hardcode AWS credentials in your Terraform files. Ever.

```bash
aws configure
# AWS Access Key ID: <your-key>
# AWS Secret Access Key: <your-secret>
# Default region name: us-east-1
# Default output format: json
```

This stores credentials in `~/.aws/credentials` — Terraform picks them up automatically.

**Verify your AWS connection:**
```bash
aws sts get-caller-identity
# Should return your AWS account ID and user ARN
```

### 2.4 Install VS Code Extension (Recommended)
Install the **HashiCorp Terraform** extension in VS Code. It gives you syntax highlighting, auto-complete, and inline documentation.

---

### 📝 Assignment 2: Setup Verification

**Task:** Prove your environment is ready.

1. Run `terraform version` and take a screenshot
2. Run `aws sts get-caller-identity` and take a screenshot showing your account ID
3. Create a folder called `terraform-training/` — this will be your workspace for all exercises

**Deliverable:** Share both screenshots with your tutor. You cannot proceed until both commands return clean output.

---

## Step 3: Your First Terraform File

Create your workspace:
```bash
mkdir terraform-training && cd terraform-training
mkdir 01-first-file && cd 01-first-file
```

Create `main.tf`:
```hcl
# This is a comment in Terraform (HCL language)

# Every Terraform project needs a terraform block
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}
```

Now run:
```bash
terraform init
```

You'll see Terraform downloading the AWS provider plugin. A `.terraform/` folder and `terraform.lock.hcl` file appear.

**What just happened?**
- Terraform downloaded the AWS provider (a plugin that knows how to talk to AWS APIs)
- `terraform.lock.hcl` pins the exact provider version — always commit this file to Git
- `.terraform/` contains the downloaded plugin — never commit this folder

### File conventions
| File | Purpose |
|---|---|
| `main.tf` | Main resources |
| `variables.tf` | Input variable declarations |
| `outputs.tf` | Output value declarations |
| `providers.tf` | Provider configuration |
| `terraform.tfvars` | Variable values (⚠️ don't commit secrets) |

---

## Step 4: Providers

A **provider** is a plugin that teaches Terraform how to talk to a specific platform. Without it, Terraform doesn't know what "AWS" means.

```hcl
# providers.tf

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"  # from registry.terraform.io/hashicorp/aws
      version = "~> 5.0"         # any 5.x version
    }
  }
}

provider "aws" {
  region = "us-east-1"

  # Optional: add default tags to ALL resources created by this provider
  default_tags {
    tags = {
      ManagedBy   = "Terraform"
      Environment = "dev"
    }
  }
}
```

### Version constraints explained
| Constraint | Meaning |
|---|---|
| `"~> 5.0"` | Allow 5.x, never 6.x (most common) |
| `">= 5.0"` | 5.0 or higher, any major version |
| `"= 5.1.0"` | Exactly this version, nothing else |
| `">= 5.0, < 6.0"` | Same as ~> 5.0, more explicit |

> **Best practice:** Always pin provider versions with `~>`. This prevents surprise breaking changes when HashiCorp releases new versions.

---

## Step 5: Resources

A **resource** is a single piece of infrastructure. Every AWS service you've used in the Console is a Terraform resource.

### Resource syntax
```hcl
resource "<PROVIDER>_<TYPE>" "<LOCAL_NAME>" {
  argument1 = "value1"
  argument2 = "value2"
}
```

### Your first real resource: an S3 bucket

```hcl
# main.tf
resource "aws_s3_bucket" "my_first_bucket" {
  bucket = "terraform-training-yourname-2024"  # must be globally unique

  tags = {
    Name    = "My First Terraform Bucket"
    Purpose = "Learning"
  }
}
```

Breaking it down:
- `aws_s3_bucket` → provider is `aws`, resource type is `s3_bucket`
- `"my_first_bucket"` → your local name, used to reference this resource elsewhere in code
- `bucket` → the argument (the actual S3 bucket name in AWS)

### Referencing one resource from another

Resources can reference each other's attributes using `<type>.<name>.<attribute>`:

```hcl
resource "aws_s3_bucket" "data" {
  bucket = "my-app-data-bucket-2024"
}

# Reference the bucket above — Terraform builds the dependency automatically
resource "aws_s3_bucket_versioning" "data" {
  bucket = aws_s3_bucket.data.id   # ← reference

  versioning_configuration {
    status = "Enabled"
  }
}
```

Terraform sees the reference and knows: create the bucket first, then enable versioning.

---

### 📝 Assignment 5: Your First Resource

**Task:** Create an S3 bucket with Terraform.

1. Inside `terraform-training/02-first-resource/`, create `main.tf`
2. Define an `aws_s3_bucket` resource with:
   - A globally unique bucket name (use your name + date)
   - Tags: `Name`, `Environment = "learning"`, `Owner = "<your name>"`
3. Run `terraform init`, `terraform plan`, `terraform apply`
4. Verify the bucket exists in the AWS Console
5. Run `terraform destroy` and verify it's gone

**Questions to answer:**
- What did `terraform plan` show before you applied?
- What happened in the Console after `terraform destroy`?

---

## Step 6: Terraform Workflow

The three commands you'll use every single day:

### `terraform init`
Downloads providers, sets up the backend. Run this once per project, or after adding new providers.
```bash
terraform init
```

### `terraform plan`
Previews what will change. **Always run this before apply.** Never skip it.
```bash
terraform plan

# Save the plan to a file (best practice for CI/CD)
terraform plan -out=tfplan
```

Read the plan output carefully:
```
+ aws_s3_bucket.data will be created     # + = create
~ aws_instance.web will be updated       # ~ = update in place
- aws_security_group.old will be destroyed  # - = destroy
-/+ aws_instance.app must be replaced    # -/+ = destroy then recreate
```

> ⚠️ `-/+` (replace) is the most dangerous. It means Terraform will **destroy** the resource and create a new one. For databases, this means data loss.

### `terraform apply`
Executes the plan. Asks for confirmation unless you pass `-auto-approve` (only do that in CI/CD).
```bash
terraform apply

# Apply a saved plan file (no confirmation prompt)
terraform apply tfplan
```

### `terraform destroy`
Destroys all resources managed by this configuration. Use carefully — especially in production.
```bash
terraform destroy
```

### `terraform fmt`
Formats all `.tf` files to standard style. Run before every commit.
```bash
terraform fmt
```

### `terraform validate`
Checks your syntax without connecting to AWS.
```bash
terraform validate
```

### Full workflow diagram
```
Write .tf files
      ↓
terraform fmt       (format)
      ↓
terraform validate  (syntax check)
      ↓
terraform plan      (preview)
      ↓
Review the plan     (human eyes)
      ↓
terraform apply     (execute)
      ↓
terraform destroy   (cleanup when done)
```

---

## Step 7: State

**State** is Terraform's memory. It's a JSON file (`terraform.tfstate`) that maps your Terraform code to real AWS resources.

### Why state exists

When you run `terraform apply` a second time, Terraform needs to know: "Does this S3 bucket already exist?" Without state, it would try to create it again and fail.

State stores the mapping:
```
aws_s3_bucket.data  →  arn:aws:s3:::my-app-data-bucket-2024  →  us-east-1
```

### Local state vs remote state

| Local State | Remote State |
|---|---|
| Stored in `terraform.tfstate` on your laptop | Stored in S3, shared by the whole team |
| Fine for learning | Required for any team project |
| No locking — two people can corrupt it | DynamoDB locking — one person at a time |
| Lost if your laptop dies | Durable and versioned |

For now you're using local state (fine for learning). We cover remote state in Level 2.

### Golden rules of state

1. **Never edit `terraform.tfstate` by hand** — use `terraform state` commands
2. **Never delete `terraform.tfstate`** — Terraform loses track of everything
3. **Never commit `terraform.tfstate` to Git** — it can contain secrets
4. Add `*.tfstate` and `*.tfstate.backup` to `.gitignore`

### Useful state commands
```bash
# See everything Terraform is managing
terraform state list

# Inspect one resource in detail
terraform state show aws_s3_bucket.data

# Remove a resource from state without destroying it in AWS
terraform state rm aws_s3_bucket.data
```

### Set up `.gitignore`
```bash
# .gitignore
.terraform/
*.tfstate
*.tfstate.backup
*.tfvars        # may contain secrets
.terraform.lock.hcl  # optional — some teams commit this
crash.log
```

---

## Step 8: Variables

Variables make your code reusable. Instead of hardcoding `"us-east-1"` everywhere, you define it once.

### Declaring variables (`variables.tf`)

```hcl
# variables.tf

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment: dev, staging, prod"
  type        = string
  default     = "dev"
}

variable "bucket_name" {
  description = "Name of the S3 bucket — must be globally unique"
  type        = string
  # No default — user must provide this value
}

variable "instance_count" {
  description = "Number of EC2 instances to create"
  type        = number
  default     = 1
}

variable "enable_versioning" {
  description = "Enable S3 bucket versioning"
  type        = bool
  default     = false
}
```

### Using variables

```hcl
# main.tf

resource "aws_s3_bucket" "app" {
  bucket = var.bucket_name           # reference with var.<name>
  region = var.aws_region

  tags = {
    Environment = var.environment
  }
}
```

### Providing variable values

**Option 1: `terraform.tfvars` file (most common)**
```hcl
# terraform.tfvars
aws_region        = "us-east-1"
environment       = "dev"
bucket_name       = "myapp-dev-data-2024"
instance_count    = 2
enable_versioning = true
```

**Option 2: Command line**
```bash
terraform apply -var="environment=prod" -var="instance_count=3"
```

**Option 3: Environment variables**
```bash
export TF_VAR_environment="prod"
export TF_VAR_bucket_name="myapp-prod-data-2024"
terraform apply
```

**Option 4: Multiple `.tfvars` files per environment**
```bash
terraform apply -var-file="dev.tfvars"
terraform apply -var-file="prod.tfvars"
```

### Variable precedence (highest wins)
```
1. -var flag on command line         ← highest priority
2. -var-file flag
3. terraform.tfvars (auto-loaded)
4. TF_VAR_* environment variables
5. default value in variable block   ← lowest priority
```

---

## Step 9: Outputs

**Outputs** expose values from your infrastructure after apply — like IP addresses, bucket names, or ARNs — so you can use them elsewhere.

```hcl
# outputs.tf

output "bucket_name" {
  description = "Name of the created S3 bucket"
  value       = aws_s3_bucket.app.bucket
}

output "bucket_arn" {
  description = "ARN of the created S3 bucket"
  value       = aws_s3_bucket.app.arn
}

output "instance_public_ip" {
  description = "Public IP of the EC2 instance — use to SSH in"
  value       = aws_instance.web.public_ip
}

output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.web.id
}
```

After `terraform apply`, outputs display automatically:
```
Outputs:

bucket_arn    = "arn:aws:s3:::myapp-dev-data-2024"
bucket_name   = "myapp-dev-data-2024"
instance_id   = "i-0abc123def456"
instance_public_ip = "54.123.45.67"
```

Retrieve outputs later:
```bash
terraform output                        # show all
terraform output instance_public_ip    # show one
terraform output -json                  # machine-readable
```

---

## Putting It All Together: EC2 + Security Group

Here is a complete, real example using everything from Steps 3–9.

**File structure:**
```
03-ec2-example/
├── main.tf
├── variables.tf
├── outputs.tf
└── terraform.tfvars
```

**`variables.tf`:**
```hcl
variable "aws_region"    { type = string; default = "us-east-1" }
variable "environment"   { type = string; default = "dev" }
variable "instance_type" { type = string; default = "t2.micro" }
variable "your_ip"       {
  type        = string
  description = "Your IP address for SSH access (format: x.x.x.x/32)"
}
```

**`main.tf`:**
```hcl
terraform {
  required_providers {
    aws = { source = "hashicorp/aws"; version = "~> 5.0" }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = { ManagedBy = "Terraform"; Environment = var.environment }
  }
}

# Security Group — controls what traffic reaches the EC2
resource "aws_security_group" "web" {
  name        = "${var.environment}-web-sg"
  description = "Allow SSH and HTTP"

  # Allow SSH from your IP only
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.your_ip]
    description = "SSH from developer IP"
  }

  # Allow HTTP from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP from internet"
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# EC2 Instance
resource "aws_instance" "web" {
  ami                    = "ami-0c55b159cbfafe1f0"   # Amazon Linux 2 (us-east-1)
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.web.id]

  tags = { Name = "${var.environment}-web-server" }
}
```

**`outputs.tf`:**
```hcl
output "public_ip"    { value = aws_instance.web.public_ip }
output "instance_id"  { value = aws_instance.web.id }
output "ssh_command"  { value = "ssh ec2-user@${aws_instance.web.public_ip}" }
```

**`terraform.tfvars`:**
```hcl
environment   = "dev"
instance_type = "t2.micro"
your_ip       = "203.0.113.5/32"   # replace with your real IP
```

---

## Level 1 Final Assignment

> **Complete this before moving to Level 2. Your tutor will review your code.**

### The Scenario
You are a new DevOps engineer at a startup. Your first task is to provision development infrastructure for the team using Terraform — no clicking in the Console allowed.

### Requirements

**Part A — S3 Storage (20 points)**
1. Create an S3 bucket with a unique name
2. Enable versioning on the bucket
3. Block all public access
4. Add tags: `Environment`, `Owner`, `Project`, `ManagedBy = "Terraform"`

**Part B — EC2 Web Server (40 points)**
1. Create a Security Group that allows:
   - SSH (port 22) from your IP only — never `0.0.0.0/0`
   - HTTP (port 80) from anywhere
   - All outbound traffic
2. Create a `t2.micro` EC2 instance using Amazon Linux 2
3. Attach the security group to the instance
4. Add a `Name` tag to the instance

**Part C — Variables & Outputs (20 points)**
1. All hardcoded values must be replaced with variables
2. Variables must have `description` and `type` defined
3. Use a `terraform.tfvars` file for values
4. Outputs must expose: `instance_public_ip`, `instance_id`, `bucket_name`, `ssh_command`

**Part D — Code Quality (20 points)**
1. Proper file structure: `main.tf`, `variables.tf`, `outputs.tf`, `terraform.tfvars`
2. All files pass `terraform fmt` with no changes
3. `terraform validate` returns "Success"
4. A `.gitignore` is present with correct entries
5. No credentials or real IPs committed

### Submission Checklist
- [ ] `terraform plan` output shared with tutor (no errors)
- [ ] `terraform apply` completed successfully
- [ ] SSH into the EC2 instance works using the output `ssh_command`
- [ ] S3 bucket visible in Console with correct tags
- [ ] `terraform destroy` completes cleanly
- [ ] All code pushed to a private Git repo

### Grading
| Score | Outcome |
|---|---|
| 90–100 | Excellent — ready for Level 2 |
| 70–89 | Good — fix noted issues, then proceed |
| Below 70 | Review Steps 5–9, redo the assignment |

---

## Key Takeaways from Level 1

- Terraform describes **desired state** — you say what you want, it figures out how
- The workflow is always: `fmt → validate → plan → review → apply`
- **Never skip `terraform plan`** — always read it before applying
- State is Terraform's memory — treat it like a database
- Variables make code reusable; outputs expose results
- **Never hardcode credentials** — use `aws configure` or IAM roles

---

*Next: [Level 2 — Intermediate](./README-intermediate.md) — Remote state, modules, VPC networking, and real team workflows*
