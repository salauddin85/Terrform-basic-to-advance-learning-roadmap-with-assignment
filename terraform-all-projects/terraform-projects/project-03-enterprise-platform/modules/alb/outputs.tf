output "alb_arn"          { value = aws_lb.main.arn }
output "alb_dns_name"     { value = aws_lb.main.dns_name }
output "alb_zone_id"      { value = aws_lb.main.zone_id }
output "alb_sg_id"        { value = aws_security_group.alb.id }
output "target_group_arn" { value = aws_lb_target_group.app.arn }
output "logs_bucket_name" { value = aws_s3_bucket.alb_logs.id }
