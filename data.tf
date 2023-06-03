# CloudFront

data "aws_cloudfront_origin_request_policy" "all_viewer_except_host_header" {
  name = "Managed-AllViewerExceptHostHeader"
}

data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

# Route 53

data "aws_route53_zone" "hosted_zone" {
  count = var.domain.create ? 1 : 0
  name  = var.domain.hosted_zone_name

  provider = aws.dns
}

# Zip Archives

data "archive_file" "server_function" {
  for_each    = local.zones_set
  type        = "zip"
  output_path = "${local.zones_map[each.value].folder_path}/server-function.zip"
  source_dir  = "${local.zones_map[each.value].folder_path}/server-function"
}

data "archive_file" "image_optimization_function" {
  type        = "zip"
  output_path = "${local.zones_map[local.root].folder_path}/image-optimization-function.zip"
  source_dir  = "${local.zones_map[local.root].folder_path}/image-optimization-function"
}

data "archive_file" "warmer_function" {
  for_each    = local.zones_set
  type        = "zip"
  output_path = "${local.zones_map[each.value].folder_path}/warmer-function.zip"
  source_dir  = "${local.zones_map[each.value].folder_path}/warmer-function"
}
