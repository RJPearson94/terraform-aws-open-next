output "cloudfront_url" {
  description = "The URL for the root cloudfront distribution"
  value       = local.use_shared_distribution ? one(module.public_resources[*].url) : module.website_zone[local.root_zone_name].cloudfront_url
}

output "alternate_domain_names" {
  description = "Extra CNAMEs (alternate domain names) associated with the cloudfront distribution"
  value       = local.use_shared_distribution ? one(module.public_resources[*].aliases) : module.website_zone[local.root_zone_name].alternate_domain_names
}

output "zones" {
  description = "Configuration details of the zones"
  value = [for zone in local.zones : {
    name                   = zone.name
    root                   = zone.root
    path                   = zone.path
    cloudfront_url         = module.website_zone[zone.name].cloudfront_url
    alternate_domain_names = module.website_zone[zone.name].alternate_domain_names
    bucket_name            = module.website_zone[zone.name].bucket_name
    }
  ]
}