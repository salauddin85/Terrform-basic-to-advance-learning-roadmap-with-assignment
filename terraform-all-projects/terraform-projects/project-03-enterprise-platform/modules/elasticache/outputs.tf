output "primary_endpoint" {
  value     = aws_elasticache_replication_group.redis.primary_endpoint_address
  sensitive = true
}
output "reader_endpoint" {
  value     = aws_elasticache_replication_group.redis.reader_endpoint_address
  sensitive = true
}
output "redis_sg_id"      { value = aws_security_group.redis.id }
output "auth_secret_arn"  { value = aws_secretsmanager_secret.redis_auth.arn }
output "port"             { value = 6379 }
