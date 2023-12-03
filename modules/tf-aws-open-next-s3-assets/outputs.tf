output "cloudfront_asset_mappings" {
  description = "Assets to be added as behaviours in CloudFront"
  value       = sort(distinct([for file in local.assets : "/${file.path_parts[0]}${length(file.path_parts) > 1 ? "/*" : ""}" if !contains(["_next", "BUILD_ID"], file.path_parts[0])]))
}

output "file_hashes" {
  description = "List of md5 hashes for each file uploaded"
  value       = concat([for asset in local.assets : asset.md5], [for cache in local.cache_assets : cache.md5], [for additional_file in local.additional_files : additional_file.md5])
}

output "asset_key_prefix" {
  description = "The prefix for assets in the bucket"
  value       = local.asset_key_prefix
}

output "origin_asset_path" {
  description = "The origin path for assets in the bucket"
  value       = local.origin_asset_path
}

output "cache_key_prefix" {
  description = "The prefix for assets in the bucket"
  value       = local.cache_key_prefix
}