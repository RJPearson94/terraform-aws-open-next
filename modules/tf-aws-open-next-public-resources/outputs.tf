output "url" {
  description = "The URL for the cloudfront distribution"
  value       = var.continuous_deployment.use ? "https://${one(aws_cloudfront_distribution.production_distribution[*].domain_name)}" : "https://${one(aws_cloudfront_distribution.website_distribution[*].domain_name)}"
}

output "arn" {
  description = "The arn for the cloudfront distribution"
  value       = var.continuous_deployment.use ? one(aws_cloudfront_distribution.production_distribution[*].arn) : one(aws_cloudfront_distribution.website_distribution[*].arn)
}

output "etag" {
  description = "The etag for the cloudfront distribution"
  value       = var.continuous_deployment.use ? coalesce(try(one(terraform_data.promote_distribution[*].output.etag), null), one(aws_cloudfront_distribution.production_distribution[*].etag)) : one(aws_cloudfront_distribution.website_distribution[*].etag)
}

output "staging_etag" {
  description = "The etag for the cloudfront staging distribution"
  value       = try(one(aws_cloudfront_distribution.staging_distribution[*].etag), null)
}

output "staging_arn" {
  description = "The arn for the cloudfront staging distribution"
  value       = try(one(aws_cloudfront_distribution.staging_distribution[*].arn), null)
}

output "aliases" {
  description = "Extra CNAMEs (alternate domain names) associated with the distribution"
  value       = local.aliases
}

output "distribution" {
  description = "The configuration of the cloudfront distribution. These are added to aid with testing"
  value       = var.continuous_deployment.use ? one(aws_cloudfront_distribution.production_distribution[*]) : one(aws_cloudfront_distribution.website_distribution[*])
}

output "staging_distribution" {
  description = "The configuration of the cloudfront distribution. These are added to aid with testing"
  value       = try(one(aws_cloudfront_distribution.staging_distribution[*]), null)
}

output "waf" {
  description = "The congiguration of the WAF ACL. These are added to aid with testing"
  value       = try(one(aws_wafv2_web_acl.distribution_waf[*]), null)
}