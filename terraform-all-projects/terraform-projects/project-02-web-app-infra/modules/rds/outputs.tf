output "db_endpoint" {
  description = "RDS endpoint — sensitive, do not log"
  value       = aws_db_instance.main.endpoint
  sensitive   = true
}

output "db_port"                  { value = aws_db_instance.main.port }
output "db_name"                  { value = aws_db_instance.main.db_name }
output "db_username"              { value = aws_db_instance.main.username }
output "db_secret_arn"            { value = aws_secretsmanager_secret.db_password.arn }
output "db_instance_id"           { value = aws_db_instance.main.id }
output "db_instance_arn"          { value = aws_db_instance.main.arn }
