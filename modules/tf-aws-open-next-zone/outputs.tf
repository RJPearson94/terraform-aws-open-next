output "alias_details" {
  description = "The alias config"
  value       = var.aliases != null ? null : one(module.open_next_aliases[*].updated_alias_mapping)
}

output "bucket_name" {
  description = "The name of the s3 bucket"
  value       = local.should_create_website_bucket ? one(aws_s3_bucket.bucket[*].id) : null
}

output "bucket_arn" {
  description = "The ARN of the s3 bucket"
  value       = local.should_create_website_bucket ? one(aws_s3_bucket.bucket[*].arn) : null
}

output "zone_config" {
  description = "The zone config"
  value       = local.zone
}

output "behaviours" {
  description = "The behaviours for the zone"
  value       = local.behaviours
}

output "custom_error_responses" {
  description = "The custom error responses for the zone"
  value       = local.custom_error_responses
}

output "cloudfront_url" {
  description = "The URL for the cloudfront distribution"
  value       = local.create_distribution ? one(module.public_resources[*].url) : null
}

output "alternate_domain_names" {
  description = "Extra CNAMEs (alternate domain names) associated with the cloudfront distribution"
  value       = local.create_distribution ? one(module.public_resources[*].aliases) : null
}