output "parameter_name" {
  description = "The name of the SSM parameter"
  value       = aws_ssm_parameter.origin_aliases.name
}

output "alias_details" {
  description = "The alias details used to update functions, s3 and CloudFront"
  value       = local.alias_details
}

output "updated_alias_mapping" {
  description = "The update alias mapping"
  value       = local.updated_alias_mapping
}