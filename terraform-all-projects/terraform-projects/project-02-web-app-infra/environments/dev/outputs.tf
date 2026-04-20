output "alb_dns_name" {
  description = "Application Load Balancer DNS — open in browser to test"
  value       = "http://${module.alb.alb_dns_name}:8080"
}

output "vpc_id"              { value = module.vpc.vpc_id }
output "public_subnet_ids"   { value = module.vpc.public_subnet_ids }
output "private_subnet_ids"  { value = module.vpc.private_subnet_ids }
output "asg_name"            { value = module.ec2.asg_name }
output "assets_bucket_name"  { value = aws_s3_bucket.assets.id }

output "db_endpoint" {
  value     = module.rds.db_endpoint
  sensitive = true
}

output "db_secret_arn" {
  description = "ARN of the Secrets Manager secret containing the DB password"
  value       = module.rds.db_secret_arn
}
