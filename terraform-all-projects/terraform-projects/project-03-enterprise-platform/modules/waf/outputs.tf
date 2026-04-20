output "web_acl_arn"  { value = aws_wafv2_web_acl.main.arn }
output "web_acl_id"   { value = aws_wafv2_web_acl.main.id }
output "log_group"    { value = aws_cloudwatch_log_group.waf.name }
