locals {
  prefix = var.prefix == null ? "" : "${var.prefix}-"
  suffix = var.suffix == null ? "" : "-${var.suffix}"

  root_zone_name          = [for zone in var.zones : zone.name if zone.root == true][0]
  zones                   = [for zone in var.zones : merge(zone, { path = var.deployment == "INDEPENDENT_ZONES" || zone.root == true ? null : coalesce(zone.path, zone.name) })]
  use_shared_distribution = contains(["SHARED_DISTRIBUTION_AND_BUCKET", "SHARED_DISTRIBUTION"], var.deployment)

  merged_static_assets = {
    zone_overrides = { for zone in local.zones : zone.name => {
      paths            = try(module.website_zone[zone.name].behaviours.static_assets.paths, null)
      additional_paths = try(module.website_zone[zone.name].behaviours.static_assets.additional_paths, null)
    } }
  }
  merged_server = {
    zone_overrides = { for zone in local.zones : zone.name => {
      paths = try(module.website_zone[zone.name].behaviours.server.paths, null)
    } }
  }
  merged_image_optimisation = {
    zone_overrides = { for zone in local.zones : zone.name => {
      paths = try(module.website_zone[zone.name].behaviours.image_optimisation.paths, null)
    } }
  }
}

module "public_resources" {
  count  = local.use_shared_distribution ? 1 : 0
  source = "../tf-aws-open-next-public-resources"

  zones = [for zone in local.zones : merge({
    root = zone.root
    name = zone.name
    path = zone.path
  }, module.website_zone[zone.name].zone_config)]

  prefix = var.prefix
  suffix = var.suffix

  enabled                   = var.distribution.enabled
  ipv6_enabled              = var.distribution.ipv6_enabled
  http_version              = var.distribution.http_version
  price_class               = var.distribution.price_class
  geo_restrictions          = var.distribution.geo_restrictions
  x_forwarded_host_function = var.distribution.x_forwarded_host_function
  auth_function             = var.distribution.auth_function

  behaviours = merge(var.behaviours, {
    static_assets      = var.behaviours.static_assets == null ? local.merged_static_assets : merge(var.behaviours.static_assets, local.merged_static_assets)
    server             = var.behaviours.server == null ? local.merged_server : merge(var.behaviours.server, local.merged_server)
    image_optimisation = var.behaviours.image_optimisation == null ? local.merged_image_optimisation : merge(var.behaviours.image_optimisation, local.merged_image_optimisation)
  })

  waf                   = var.waf
  domain_config         = var.domain_config
  continuous_deployment = var.continuous_deployment

  custom_error_responses = module.website_zone[local.root_zone_name].custom_error_responses

  providers = {
    aws     = aws.global
    aws.dns = aws.dns
    aws.iam = aws.iam
  }
}

# S3

resource "aws_s3_bucket" "shared_bucket" {
  count         = var.deployment == "SHARED_DISTRIBUTION_AND_BUCKET" ? 1 : 0
  bucket        = "${local.prefix}website-bucket${local.suffix}"
  force_destroy = var.website_bucket.force_destroy
}

resource "aws_s3_bucket_policy" "shared_bucket_policy" {
  count  = var.deployment == "SHARED_DISTRIBUTION_AND_BUCKET" ? 1 : 0
  bucket = one(aws_s3_bucket.shared_bucket[*].id)
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Principal" : {
          "Service" : "cloudfront.amazonaws.com"
        },
        "Action" : [
          "s3:GetObject"
        ],
        "Resource" : "${one(aws_s3_bucket.shared_bucket[*].arn)}/*",
        "Effect" : "Allow",
        "Condition" : {
          "StringEquals" : {
            "AWS:SourceArn" : compact([try(one(module.public_resources[*].arn), null), try(one(module.public_resources[*].staging_arn), null)])
          }
        }
      }
    ]
  })
}

# Zones

module "website_zone" {
  for_each = { for zone in local.zones : zone.name => zone }
  source   = "../tf-aws-open-next-zone"

  prefix = "${local.prefix}${each.value.name}"
  suffix = var.suffix

  folder_path = each.value.folder_path

  zone_suffix                          = each.value.path
  s3_folder_prefix                     = var.deployment == "SHARED_DISTRIBUTION_AND_BUCKET" ? each.value.name : null
  s3_exclusion_regex                   = try(coalesce(each.value.s3_exclusion_regex, var.s3_exclusion_regex), null)
  function_architecture                = try(coalesce(each.value.function_architecture, var.function_architecture), null)
  iam                                  = try(coalesce(each.value.iam, var.iam), null)
  cloudwatch_log                       = try(coalesce(each.value.cloudwatch_log, var.cloudwatch_log), null)
  vpc                                  = try(coalesce(each.value.vpc, var.vpc), null)
  aliases                              = try(coalesce(each.value.aliases, var.aliases), null)
  cache_control_immutable_assets_regex = try(coalesce(each.value.cache_control_immutable_assets_regex, var.cache_control_immutable_assets_regex), null)
  content_types                        = try(coalesce(each.value.content_types, var.content_types), null)

  warmer_function             = try(coalesce(each.value.warmer_function, var.warmer_function), null)
  server_function             = try(coalesce(each.value.server_function, var.server_function), null)
  image_optimisation_function = try(coalesce(each.value.image_optimisation_function, var.image_optimisation_function), null)
  revalidation_function       = try(coalesce(each.value.revalidation_function, var.revalidation_function), null)

  behaviours     = try(coalesce(each.value.behaviours, var.behaviours), null)
  tag_mapping_db = try(coalesce(each.value.tag_mapping_db, var.tag_mapping_db), null)

  website_bucket         = var.deployment != "SHARED_DISTRIBUTION_AND_BUCKET" ? merge(try(coalesce(each.value.website_bucket, var.website_bucket), {}), { deployment = "CREATE", create_bucket_policy = var.deployment == "INDEPENDENT_ZONES" }) : { deployment = "NONE", arn = one(aws_s3_bucket.shared_bucket[*].arn), name = one(aws_s3_bucket.shared_bucket[*].id), region = data.aws_region.current.name, domain_name = one(aws_s3_bucket.shared_bucket[*].bucket_regional_domain_name) }
  distribution           = var.deployment == "INDEPENDENT_ZONES" ? try(coalesce(each.value.distribution, var.distribution), {}) : { deployment = "NONE", enabled = null, ipv6_enabled = null, http_version = null, price_class = null, geo_restrictions = null, x_forwarded_host_function = null, auth_function = null }
  waf                    = try(coalesce(each.value.waf, var.waf), null)
  domain_config          = try(coalesce(each.value.domain_config, var.domain_config), null)
  continuous_deployment  = coalesce(each.value.continuous_deployment, var.continuous_deployment)
  custom_error_responses = var.deployment == "INDEPENDENT_ZONES" || each.value.root == true ? try(coalesce(each.value.custom_error_responses, var.custom_error_responses), {}) : []

  providers = {
    aws.global          = aws.global
    aws.dns             = aws.dns
    aws.iam             = aws.iam
    aws.server_function = aws.server_function
  }
}

# Move to the multi-zone to prevent a cyclic dependency
resource "aws_s3_bucket_policy" "shared_distribution_bucket_policy" {
  for_each = var.deployment == "SHARED_DISTRIBUTION" ? { for zone in local.zones : zone.name => zone } : {}
  bucket   = module.website_zone[each.key].bucket_name
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Principal" : {
          "Service" : "cloudfront.amazonaws.com"
        },
        "Action" : [
          "s3:GetObject"
        ],
        "Resource" : "${module.website_zone[each.key].bucket_arn}/*",
        "Effect" : "Allow",
        "Condition" : {
          "StringEquals" : {
            "AWS:SourceArn" : compact([try(one(module.public_resources[*].arn), null), try(one(module.public_resources[*].staging_arn), null)])
          }
        }
      }
    ]
  })
}