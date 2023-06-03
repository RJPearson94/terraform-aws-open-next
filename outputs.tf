output "cloudfront_url" {
  description = "The URL for the cloudfront distribution"
  value       = "https://${aws_cloudfront_distribution.website_distribution.domain_name}"
}

output "domain_names" {
  description = "The custom domain names attached to the cloudfront distribution"
  value       = [for alias in local.aliases : "https://${alias}"]
}
