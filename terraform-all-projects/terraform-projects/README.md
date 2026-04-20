# Terraform Projects — Solution Code

Complete, production-ready solution code for all three hands-on projects.
Read `PROJECTS.md` first for the full project descriptions and requirements.

---

## Quick Start — Each Project

### Project 01 — Static Website (Easy)

```bash
cd project-01-static-website/

# 1. Edit terraform.tfvars with your project name
# 2. Deploy
terraform init
terraform plan
terraform apply

# 3. Get your website URL
terraform output website_url

# 4. Teardown
terraform destroy
```

**Expected output after apply:**
```
website_url = "https://d1abcdef1234.cloudfront.net"
```

---

### Project 02 — Three-Tier Web App (Medium)

```bash
# Step 1: Bootstrap remote state (one-time)
cd project-02-web-app-infra/bootstrap/
terraform init
terraform apply
# Note the bucket name and table name from outputs

# Step 2: Update backend config
cd ../environments/dev/
# Edit main.tf — replace ACCOUNT_ID in the backend block

# Step 3: Deploy
terraform init    # type 'yes' to migrate state
terraform plan
terraform apply

# Step 4: Test
terraform output alb_dns_name
# Open http://<alb-dns>:8080 in browser — should see "Hello from webapp (dev)"

# Step 5: Teardown
terraform destroy
cd ../../bootstrap && terraform destroy
```

**Expected output after apply:**
```
alb_dns_name    = "http://webapp-dev-alb-1234567890.us-east-1.elb.amazonaws.com:8080"
asg_name        = "webapp-dev-asg"
assets_bucket   = "webapp-dev-assets-123456789012"
db_secret_arn   = "arn:aws:secretsmanager:..."
```

---

### Project 03 — Enterprise Platform (Complex)

```bash
# Prerequisites: install Terragrunt
# macOS: brew install terragrunt
# Linux: see https://terragrunt.gruntwork.io/docs/getting-started/install/

# Step 1: Create the S3 state bucket manually (bootstrap for Terragrunt)
aws s3api create-bucket \
  --bucket enterprise-terraform-state-$(aws sts get-caller-identity --query Account --output text) \
  --region us-east-1

aws s3api put-bucket-versioning \
  --bucket enterprise-terraform-state-$(aws sts get-caller-identity --query Account --output text) \
  --versioning-configuration Status=Enabled

aws dynamodb create-table \
  --table-name enterprise-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1

# Step 2: Plan the entire dev environment
cd project-03-enterprise-platform/environments/dev/
terragrunt run-all plan --terragrunt-parallelism 4

# Step 3: Apply in dependency order (Terragrunt handles this automatically)
terragrunt run-all apply --terragrunt-parallelism 4

# Step 4: Run tests
cd ../../
terraform test -test-directory=tests/

# Step 5: Teardown (reverse dependency order)
cd environments/dev/
terragrunt run-all destroy --terragrunt-parallelism 4
```

**Expected apply order (Terragrunt resolves this automatically):**
```
1. kms           (no dependencies)
2. vpc           (depends on kms)
3. alb           (depends on vpc)
4. ecs           (depends on vpc, alb, aurora)
5. aurora        (depends on vpc, kms, ecs)
6. elasticache   (depends on vpc, kms, ecs)
7. waf           (depends on alb)
```

---

## Folder Structure Overview

```
solutions/
├── .gitignore
│
├── project-01-static-website/          # Easy
│   ├── main.tf                         # S3 + CloudFront + OAC
│   ├── variables.tf
│   ├── outputs.tf
│   ├── terraform.tfvars
│   └── .gitignore
│
├── project-02-web-app-infra/           # Medium
│   ├── bootstrap/                      # remote state setup (run once)
│   │   └── main.tf
│   ├── modules/
│   │   ├── vpc/                        # VPC + subnets + NAT + routes
│   │   ├── security/                   # Security groups (ALB, EC2, RDS)
│   │   ├── alb/                        # Application Load Balancer
│   │   ├── ec2/                        # Launch Template + ASG + IAM
│   │   └── rds/                        # RDS PostgreSQL + Secrets Manager
│   └── environments/
│       └── dev/                        # wires all modules together
│           ├── main.tf
│           ├── variables.tf
│           ├── outputs.tf
│           └── terraform.tfvars
│
└── project-03-enterprise-platform/    # Complex
    ├── terragrunt.hcl                  # root: auto-generates backend + provider
    ├── .github/
    │   └── workflows/
    │       ├── terraform-ci.yml        # PR: lint, security scan, plan
    │       └── drift-detection.yml     # daily: detect manual changes
    ├── modules/
    │   ├── kms/                        # Customer-managed KMS key
    │   ├── vpc/                        # 3-tier VPC + flow logs + VPC endpoints
    │   ├── alb/                        # ALB + access logs + security group
    │   ├── ecs/                        # ECS Fargate + autoscaling + IAM
    │   ├── aurora/                     # Aurora Serverless v2 + Secrets Manager
    │   ├── elasticache/                # Redis + auth token + encryption
    │   ├── waf/                        # WAF v2 + managed rules + logging
    │   └── monitoring/                 # CloudWatch dashboard + alarms + SNS
    ├── environments/
    │   ├── dev/
    │   │   ├── env.hcl
    │   │   ├── terragrunt.hcl
    │   │   ├── kms/terragrunt.hcl
    │   │   ├── vpc/terragrunt.hcl
    │   │   ├── alb/terragrunt.hcl
    │   │   ├── ecs/terragrunt.hcl
    │   │   ├── aurora/terragrunt.hcl
    │   │   ├── elasticache/terragrunt.hcl
    │   │   └── waf/terragrunt.hcl
    │   └── prod/
    │       ├── env.hcl
    │       ├── vpc/terragrunt.hcl      # 3 AZs, one NAT per AZ
    │       └── aurora/terragrunt.hcl   # larger ACU, 2 instances, 30d backup
    └── tests/
        ├── vpc_test.tftest.hcl         # 6 assertions: CIDR, subnets, routes, tags
        └── kms_test.tftest.hcl         # rotation, alias, deletion window
```

---

## Cost Estimates (AWS, us-east-1)

| Project | Service | Monthly Cost |
|---|---|---|
| **Project 01** | S3 (< 1GB) | ~$0.02 |
| | CloudFront (free tier) | $0.00 |
| | **Total** | **~$0.02/mo** |
| **Project 02** | 2× t3.micro EC2 | ~$15 |
| | db.t3.micro RDS | ~$15 |
| | NAT Gateway (if enabled) | ~$32 |
| | ALB | ~$16 |
| | **Total** | **~$46–78/mo** |
| **Project 03** | ECS Fargate (2 tasks) | ~$10 |
| | Aurora Serverless v2 (min) | ~$50 |
| | ElastiCache t3.micro | ~$12 |
| | ALB | ~$16 |
| | NAT Gateway (×2) | ~$64 |
| | WAF | ~$6 |
| | **Total** | **~$158/mo** |

> ⚠️ Always run `terraform destroy` or `terragrunt run-all destroy` when you
> are done to avoid unexpected charges. Project 03 should never be left running
> for more than a few hours during learning.

---

## Common Errors and Fixes

| Error | Cause | Fix |
|---|---|---|
| `BucketAlreadyExists` | S3 bucket names are global | Add your account ID or a random suffix to the bucket name |
| `InvalidClientTokenId` | Wrong AWS credentials | Run `aws configure` and verify with `aws sts get-caller-identity` |
| `EntityAlreadyExists` (IAM) | Role name already exists in account | Change `name_prefix` in terraform.tfvars |
| `terraform init` fails on backend | State bucket doesn't exist | Run the bootstrap first |
| CloudFront returns 403 | Bucket policy not applied yet | Wait 2–3 min and retry; CloudFront propagation takes time |
| ECS tasks fail health check | Container not listening on expected port | Check `container_port` matches what your container actually listens on |
| Aurora `InvalidParameterCombination` | Serverless v2 requires `engine_mode = "provisioned"` | Verify the engine_mode setting in the aurora module |
| Terragrunt `Error reading outputs` | Dependency not yet applied | Apply dependencies first or use `mock_outputs` for plan |
