output "key_id"     { value = aws_kms_key.main.key_id }
output "key_arn"    { value = aws_kms_key.main.arn }
output "alias_arn"  { value = aws_kms_alias.main.arn }
output "alias_name" { value = aws_kms_alias.main.name }
