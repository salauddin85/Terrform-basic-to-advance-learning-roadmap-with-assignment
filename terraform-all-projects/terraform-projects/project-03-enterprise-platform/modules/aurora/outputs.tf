output "cluster_endpoint" {
  value     = aws_rds_cluster.main.endpoint
  sensitive = true
}
output "reader_endpoint" {
  value     = aws_rds_cluster.main.reader_endpoint
  sensitive = true
}
output "cluster_id"          { value = aws_rds_cluster.main.id }
output "cluster_arn"         { value = aws_rds_cluster.main.arn }
output "db_name"             { value = aws_rds_cluster.main.database_name }
output "secret_arn"          { value = aws_secretsmanager_secret.aurora_password.arn }
output "aurora_sg_id"        { value = aws_security_group.aurora.id }
