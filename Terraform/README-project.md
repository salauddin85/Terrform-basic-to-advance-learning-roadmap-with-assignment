# Terraform Hands-On Projects
> Three industry-grade projects for DevOps interns — from Basic to Advanced.  
> Each project is resume-worthy and mirrors real work done at tech companies.

---

## How to Use This Document

1. Read the project description fully before writing a single line of code
2. Try to build it yourself first — struggle is where learning happens
3. If you're stuck for more than 30 minutes on one problem, consult the solution code
4. After completing each project, deploy it, test it, then tear it down cleanly

**Solution code locations:**
- Easy → `solutions/project-01-static-website/`
- Medium → `solutions/project-02-web-app-infra/`
- Complex → `solutions/project-03-enterprise-platform/`

---

## Project 01 — Static Website Hosting on AWS S3 + CloudFront
**Level:** Easy (Basic)  
**Estimated time:** 4–6 hours  
**Resume tag:** *Provisioned serverless static website hosting on AWS using Terraform with CloudFront CDN, HTTPS, and automated cache invalidation*

---

### Project Description

Your company's marketing team needs a static website hosted on AWS. The site must load fast globally, serve over HTTPS, and cost almost nothing to run. You've been asked to provision the entire infrastructure using Terraform so it can be reproduced in minutes for any future project.

**What you will build:**

```
Internet Users (Global)
        |
   CloudFront CDN
   (HTTPS, edge cache)
        |
   S3 Bucket
   (private, website files)
        |
  Origin Access Control
  (CloudFront-only access)
```

**AWS services used:**
- S3 (static file hosting)
- CloudFront (global CDN + HTTPS)
- ACM (SSL/TLS certificate) — optional for custom domain
- Route53 (DNS) — optional for custom domain

### Step-by-Step Goals

**Step 1 — S3 Bucket**
- Create a private S3 bucket (NOT public — CloudFront will access it)
- Enable versioning
- Block all public access
- Upload a sample `index.html` and `error.html`

**Step 2 — Origin Access Control (OAC)**
- Create a CloudFront Origin Access Control
- Write an S3 bucket policy that only allows CloudFront to read objects

**Step 3 — CloudFront Distribution**
- Create a CloudFront distribution pointing to the S3 bucket
- Enable HTTPS (use the default CloudFront certificate for now)
- Set default root object to `index.html`
- Configure custom error responses (404 → error.html)
- Set cache behaviour: cache for 1 day, forward no cookies or headers

**Step 4 — Outputs**
- Output the CloudFront domain name (e.g. `d1234abcd.cloudfront.net`)
- Output the S3 bucket name
- Output the website URL

### Deliverables
- Infrastructure provisioned via `terraform apply`
- Navigate to the CloudFront URL in a browser → see your HTML page
- `terraform destroy` removes everything cleanly

---

### Important Considerations & Best Practices

**Security**
- The S3 bucket must be PRIVATE. Never enable public website hosting on S3 directly — it exposes your bucket to the internet without CloudFront protection
- Use Origin Access Control (OAC), not the older Origin Access Identity (OAI) — OAC is the current AWS recommendation
- Always enforce HTTPS — set `viewer_protocol_policy = "redirect-to-https"` in CloudFront

**Cost**
- S3 costs ~$0.023/GB storage + $0.0004/1000 requests — essentially free for small sites
- CloudFront free tier: 1TB data transfer + 10M requests/month — free for development
- ACM certificates are free

**Performance**
- Set `compress = true` on CloudFront to enable Gzip/Brotli compression automatically
- Choose the right `price_class`: `PriceClass_100` (US+Europe) is cheapest; `PriceClass_All` is fastest globally

**Terraform-specific**
- The `aws_s3_object` resource can upload your HTML files — use it for the sample files
- CloudFront distributions take 5–15 minutes to deploy — this is normal
- Use `depends_on` between the bucket policy and the CloudFront distribution

**Common mistakes to avoid**
- Forgetting `default_root_object = "index.html"` → you'll get 403 errors
- Using `s3-website` endpoint instead of the bucket domain → breaks OAC
- Not waiting for CloudFront to finish deploying before testing

---

## Project 02 — Three-Tier Web Application Infrastructure
**Level:** Medium (Intermediate)  
**Estimated time:** 8–12 hours  
**Resume tag:** *Architected and provisioned a production-grade three-tier AWS infrastructure (VPC, ALB, Auto Scaling EC2, RDS PostgreSQL) using modular Terraform with remote state and CI/CD pipeline*

---

### Project Description

A startup has built a web application and needs a proper AWS infrastructure for it. You are the DevOps engineer responsible for provisioning everything from scratch. The architecture must be highly available (multi-AZ), scalable (Auto Scaling), and follow AWS security best practices.

**What you will build:**

```
Internet
    |
Application Load Balancer (public subnets, 2 AZs)
    |
Auto Scaling Group — EC2 t3.micro (private subnets, 2 AZs)
    |
RDS PostgreSQL (private subnets, Multi-AZ)
    |
S3 Bucket (application assets)

Supporting:
- VPC with public + private subnets across 2 AZs
- NAT Gateway (private instances reach internet for updates)
- Security Groups (layered: ALB → EC2 → RDS)
- IAM Role (EC2 can read S3 and Secrets Manager)
- Remote state (S3 + DynamoDB)
```

**AWS services used:** VPC, EC2, ALB, Auto Scaling, RDS, S3, IAM, Secrets Manager

### Step-by-Step Goals

**Step 1 — Remote State Bootstrap**
- Create a separate `bootstrap/` directory
- Provision S3 bucket (versioning + encryption) + DynamoDB lock table
- Configure all other environments to use this as their backend

**Step 2 — Networking Module (`modules/vpc`)**
- VPC with custom CIDR
- 2 public subnets + 2 private subnets across 2 AZs
- Internet Gateway, NAT Gateway (1, in first public subnet)
- Public route table (→ IGW) + private route table (→ NAT)
- All resources tagged with environment and project

**Step 3 — Security Module (`modules/security`)**
- ALB Security Group: allow 80 + 443 from `0.0.0.0/0`
- EC2 Security Group: allow 80 from ALB SG only (not the internet)
- RDS Security Group: allow 5432 from EC2 SG only
- No security group should allow SSH from `0.0.0.0/0`

**Step 4 — Compute Module (`modules/ec2`)**
- Launch Template with Amazon Linux 2, t3.micro, user_data installs Apache
- Auto Scaling Group: min=1, max=3, desired=2
- Scale out when CPU > 70% (CloudWatch alarm + scaling policy)
- EC2 instances attach IAM role (read S3 + Secrets Manager)

**Step 5 — Database Module (`modules/rds`)**
- RDS PostgreSQL 14, db.t3.micro, 20GB gp3
- Placed in private subnets
- Automated backups (7 day retention)
- Password stored in AWS Secrets Manager (not in tfvars)
- `deletion_protection = true`

**Step 6 — Load Balancer Module (`modules/alb`)**
- Application Load Balancer in public subnets
- Target group pointing to the Auto Scaling Group
- HTTP listener redirects to HTTPS (or just HTTP for this project)
- Health check: GET / → expect 200

**Step 7 — Root Module + Environments**
- `environments/dev/` wires all modules together for dev
- All values in `dev.tfvars`, no hardcoding in `.tf` files
- Outputs: ALB DNS name, RDS endpoint (sensitive), ASG name

### Deliverables
- `terraform apply` deploys the full stack
- ALB DNS name resolves and returns HTTP 200
- RDS is reachable from EC2 (not from internet)
- `terraform destroy` removes everything with no errors

---

### Important Considerations & Best Practices

**Architecture**
- Multi-AZ is not optional for production — your ALB, ASG, and RDS must span 2+ AZs
- Never put RDS in a public subnet — it should only be reachable from EC2
- The NAT Gateway costs ~$32/month — acceptable for staging/prod, can skip for dev

**Security (the most important section)**
- Security groups use security group IDs as sources, not CIDR blocks, for inter-service communication — e.g., EC2 SG allows traffic from ALB SG, not `0.0.0.0/0`
- RDS passwords must never appear in `.tf` files, `.tfvars`, or state files — use `random_password` resource + Secrets Manager
- EC2 instances should use IAM roles, not access keys — never hardcode AWS credentials
- Use `sensitive = true` on the RDS endpoint output to prevent it appearing in logs

**Reliability**
- Auto Scaling health checks should use ELB type (not EC2 type) — lets the ASG replace unhealthy instances that the ALB detects
- Set `create_before_destroy = true` on the ASG Launch Template for zero-downtime updates
- RDS `backup_retention_period` should be at least 7 days

**Terraform code quality**
- Each module should be independently testable — you should be able to `terraform apply` the VPC module alone
- Use `data "aws_availability_zones"` to fetch AZs dynamically — don't hardcode `us-east-1a`
- Tag every resource with at minimum: `Environment`, `Project`, `ManagedBy = "Terraform"`

**Common mistakes**
- Circular dependencies between security groups: create them first, then add rules as separate `aws_security_group_rule` resources
- RDS needs 2 subnets in different AZs — use `aws_db_subnet_group`
- ALB target group must be attached to the ASG, not individual instances — use `aws_autoscaling_attachment`

---

## Project 03 — Enterprise Multi-Environment Platform with Terragrunt
**Level:** Complex (Advanced)  
**Estimated time:** 2–3 days  
**Resume tag:** *Designed and implemented an enterprise-grade multi-environment AWS platform using Terraform + Terragrunt, including ECS Fargate, RDS Aurora, ElastiCache Redis, WAF, security scanning pipeline, drift detection, and automated testing*

---

### Project Description

You are the Lead DevOps Engineer at a growing tech company. The engineering team is deploying a containerized microservice and needs a production-ready platform that can handle real traffic, pass a security audit, and be maintained by a team of 10 engineers across 3 environments (dev, staging, prod).

This project is what senior DevOps engineers build. It uses Terragrunt to eliminate backend config repetition, ECS Fargate for containerized workloads, Aurora for a managed database cluster, ElastiCache for caching, WAF for application security, and a full CI/CD + security pipeline.

**What you will build:**

```
Internet
    |
WAF (Web Application Firewall)
    |
ALB (Application Load Balancer) — HTTPS only
    |
ECS Fargate Service (2 tasks, private subnets)
    |
  +------------------+------------------+
  |                  |                  |
Aurora PostgreSQL  ElastiCache Redis   S3 Assets
(Serverless v2)    (Redis 7)          (+ CloudFront)
  |
Secrets Manager (DB creds, API keys)
  |
KMS (encryption for everything)

Supporting:
- VPC with 3 tiers: public, private-app, private-data
- 3 environments: dev, staging, prod (Terragrunt)
- CloudWatch dashboards + alarms
- Drift detection pipeline (daily)
- Security scanning (tfsec + checkov) in CI
- Native Terraform tests
```

**AWS services used:** VPC, ECS Fargate, ALB, Aurora Serverless v2, ElastiCache, S3, CloudFront, WAF, KMS, Secrets Manager, CloudWatch, IAM, ACM

### Step-by-Step Goals

**Step 1 — Terragrunt Foundation**
- Root `terragrunt.hcl`: auto-generates backend config for every module
- Environment-level `terragrunt.hcl`: sets common variables (project, region, account_id)
- Module-level `terragrunt.hcl` files with `dependency` blocks
- `terragrunt run-all plan` works on the entire `dev/` directory

**Step 2 — KMS + Secrets Foundation (`modules/kms`, `modules/secrets`)**
- Customer-managed KMS key with rotation enabled
- Secrets Manager secret for Aurora password (generated by Terraform)
- Secrets Manager secret for any API keys
- KMS key policy: only the current account, no `*` principals

**Step 3 — Three-Tier VPC (`modules/vpc`)**
- 3 subnet tiers: public, private-app, private-data
- 2 AZs minimum (3 for prod)
- NAT Gateway: single in dev, one-per-AZ in prod (for HA)
- VPC Flow Logs to CloudWatch (90-day retention)
- VPC Endpoints for S3 and ECR (reduce NAT costs)

**Step 4 — ECS Fargate (`modules/ecs`)**
- ECS Cluster with Container Insights enabled
- Task Definition: 256 CPU / 512 MB memory, pulls from ECR
- Service: desired_count=2, spread across AZs
- Auto Scaling: scale on CPU > 60% and memory > 80%
- Task role: read Secrets Manager + S3
- Execution role: pull from ECR + write CloudWatch Logs

**Step 5 — Aurora Serverless v2 (`modules/aurora`)**
- Aurora PostgreSQL Serverless v2 cluster
- Min ACU = 0.5 (dev) / 2 (prod), Max ACU = 4 (dev) / 32 (prod)
- Encrypted with KMS customer key
- Automated backups: 7 days (dev) / 30 days (prod)
- `deletion_protection = true` (prod only)
- Password from Secrets Manager — no hardcoding

**Step 6 — ElastiCache Redis (`modules/elasticache`)**
- Redis 7 replication group
- 1 shard, 1 replica (dev) / 1 shard, 2 replicas (prod)
- In-transit + at-rest encryption
- Auth token from Secrets Manager

**Step 7 — WAF + ALB (`modules/waf`, `modules/alb`)**
- WAF v2 WebACL with AWS Managed Rules:
  - `AWSManagedRulesCommonRuleSet`
  - `AWSManagedRulesKnownBadInputsRuleSet`
  - `AWSManagedRulesSQLiRuleSet`
- Rate limiting rule: 1000 requests/5 min per IP
- ALB with WAF attached
- HTTPS listener with ACM certificate
- HTTP → HTTPS redirect

**Step 8 — Observability (`modules/monitoring`)**
- CloudWatch Dashboard: ECS CPU/memory, ALB request count, Aurora connections, Redis hits
- Alarms: ECS CPU > 80%, ALB 5xx > 1%, Aurora storage > 80%
- SNS topic for alarm notifications

**Step 9 — CI/CD + Security Pipeline**
- GitHub Actions: fmt, validate, tfsec, checkov, plan on PR
- Apply on merge to main (per environment)
- Daily drift detection workflow with Slack alerts
- Native Terraform tests for VPC and ECS modules

### Deliverables
- `terragrunt run-all apply` on `dev/` provisions the full stack
- ECS service runs 2 healthy tasks (use the nginx public image if you don't have your own)
- ALB HTTPS endpoint returns 200
- All tfsec + checkov checks pass
- Terraform tests pass
- Drift detection pipeline runs on schedule

---

### Important Considerations & Best Practices

**Terragrunt**
- The root `terragrunt.hcl` is the single source of truth for backend config — if you change the bucket name, change it once
- Use `dependency` mock outputs for `validate` and `plan` — otherwise Terragrunt tries to read real outputs before dependencies are applied
- Run `terragrunt run-all plan --terragrunt-parallelism 4` to limit parallel executions and avoid AWS rate limiting

**ECS Fargate**
- Task definitions are immutable — every change creates a new revision. This is by design; don't try to fight it
- Never put secrets in task definition environment variables — they appear in the ECS console in plaintext. Use `secrets` with Secrets Manager ARNs instead
- ECS service auto scaling requires the application auto scaling service-linked role to exist in your account

**Aurora Serverless v2**
- Serverless v2 scales in ACU increments — set min ACU to 0.5 for dev to minimise costs (scales to zero is NOT supported in v2 — that's v1)
- Aurora cluster requires a `aws_rds_cluster_instance` even for Serverless v2 — this is a common confusion
- Use `engine_mode = "provisioned"` with `serverlessv2_scaling_configuration` for Serverless v2

**WAF**
- WAF costs $5/month per WebACL + $1/month per rule — not free, but essential for production
- Test WAF rules in COUNT mode before switching to BLOCK — you don't want to block legitimate traffic
- Always attach WAF to the ALB, not to individual services

**Security**
- Every secret must be created with `lifecycle { ignore_changes = [secret_string] }` after initial creation — otherwise Terraform will reset the password on every apply
- KMS key policies must explicitly grant the root account access — without it, you can lock yourself out
- Use `aws_iam_role_policy` (inline) for task-specific permissions, `aws_iam_role_policy_attachment` for managed policies

**Multi-environment with Terragrunt**
- Dev and prod should differ in: instance sizes, replica counts, backup retention, deletion protection, NAT gateway count
- Never copy-paste `terragrunt.hcl` between environments — use `inputs =` to pass environment-specific values
- The `dependency` block `mock_outputs` should return realistic values that match the real output types

**Drift detection**
- Run drift detection against prod daily at minimum — manual Console changes are common in incident response
- `terraform plan -refresh-only -detailed-exitcode` returns exit code 2 if drift is detected — use this in your pipeline
- Send alerts to a dedicated `#infra-alerts` Slack channel, not general engineering channels

---

## Skills Demonstrated by Project Level

| Skill | Project 01 | Project 02 | Project 03 |
|---|:---:|:---:|:---:|
| S3, CloudFront, IAM | ✓ | ✓ | ✓ |
| Variables, outputs, state | ✓ | ✓ | ✓ |
| Modules | | ✓ | ✓ |
| VPC networking | | ✓ | ✓ |
| RDS, Auto Scaling, ALB | | ✓ | ✓ |
| Remote state + CI/CD | | ✓ | ✓ |
| Terragrunt | | | ✓ |
| ECS Fargate | | | ✓ |
| Aurora Serverless | | | ✓ |
| KMS, WAF, ElastiCache | | | ✓ |
| Security scanning | | | ✓ |
| Terraform testing | | | ✓ |
| Drift detection | | | ✓ |

---

*Solution code: see `solutions/` directory*