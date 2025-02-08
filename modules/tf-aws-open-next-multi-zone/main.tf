locals {
  prefix = var.prefix == null ? "" : "${var.prefix}-"
  suffix = var.suffix == null ? "" : "-${var.suffix}"

  root_zone_name          = [for zone in var.zones : zone.name if zone.root == true][0]
  zones                   = [for zone in var.zones : merge(zone, { path = var.deployment == "INDEPENDENT_ZONES" || zone.root == true ? null : coalesce(zone.path, zone.name) })]
  use_shared_distribution = contains(["SHARED_DISTRIBUTION_AND_BUCKET", "SHARED_DISTRIBUTION"], var.deployment)

  function_url_permission_details = local.use_shared_distribution ? merge(flatten([
    for zone in local.zones : [
      for distribution_name in try(one(module.public_resources[*].distributions_provisioned), []) : [
        for alias in try(module.website_zone[zone.name].alias_details, []) : {
          for origin_name in try(module.website_zone[zone.name].zone_config.origin_names, []) : "${distribution_name}-${zone.name}-${alias}-${origin_name}" => {
            function_name     = module.website_zone[zone.name].zone_config.origins[origin_name].backend_name
            auth              = module.website_zone[zone.name].zone_config.origins[origin_name].auth
            zone_name         = zone.name,
            distribution_name = distribution_name,
            alias             = alias
          } if module.website_zone[zone.name].zone_config.origins[origin_name].auth == "OAC"
        }
      ]
    ]
  ])...) : {}

  merged_static_assets = {
    zone_overrides = { for zone in local.zones : zone.name => {
      paths            = try(module.website_zone[zone.name].behaviours.static_assets.paths, null)
      additional_paths = try(module.website_zone[zone.name].behaviours.static_assets.additional_paths, null)
    } }
  }
  merged_server = {
    zone_overrides = { for zone in local.zones : zone.name => {
      paths          = try(module.website_zone[zone.name].behaviours.server.paths, null)
      origin_request = try(module.website_zone[zone.name].behaviours.server.origin_request, null)
      path_overrides = try(module.website_zone[zone.name].behaviours.server.path_overrides, null)
    } }
  }
  merged_additional_origins = merge([for zone in local.zones : {
    for name, origin in try(module.website_zone[zone.name].behaviours.additional_origins, {}) : "${zone.name}-${name}" => origin
  }]...)
  merged_image_optimisation = {
    zone_overrides = { for zone in local.zones : zone.name => {
      paths = try(module.website_zone[zone.name].behaviours.image_optimisation.paths, null)
    } }
  }
}

module "public_resources" {
  count  = local.use_shared_distribution ? 1 : 0
  source = "../tf-aws-open-next-public-resources"

  zones = [for zone in local.zones : merge(module.website_zone[zone.name].zone_config, {
    root    = zone.root
    name    = zone.name
    path    = zone.path
    origins = { for name, origin in module.website_zone[zone.name].zone_config.origins : contains(["server", "static_assets", "image_optimisation"], name) ? name : "${zone.name}-${name}" => origin }
  })]

  prefix = var.prefix
  suffix = var.suffix

  enabled                   = var.distribution.enabled
  ipv6_enabled              = var.distribution.ipv6_enabled
  http_version              = var.distribution.http_version
  price_class               = var.distribution.price_class
  geo_restrictions          = var.distribution.geo_restrictions
  x_forwarded_host_function = var.distribution.x_forwarded_host_function
  auth_function             = var.distribution.auth_function
  cache_policy              = var.distribution.cache_policy

  behaviours = merge(var.behaviours, {
    static_assets      = var.behaviours.static_assets == null ? local.merged_static_assets : merge(var.behaviours.static_assets, local.merged_static_assets)
    server             = var.behaviours.server == null ? local.merged_server : merge(var.behaviours.server, local.merged_server)
    image_optimisation = var.behaviours.image_optimisation == null ? local.merged_image_optimisation : merge(var.behaviours.image_optimisation, local.merged_image_optimisation)
    additional_origins = var.behaviours.additional_origins == null ? local.merged_additional_origins : merge(var.behaviours.additional_origins, local.merged_additional_origins)
  })

  waf                   = var.waf
  domain_config         = var.domain_config
  continuous_deployment = var.continuous_deployment

  custom_error_responses = module.website_zone[local.root_zone_name].custom_error_responses

  open_next_version_alias = can(regex("^v2\\.[0-9x]+\\.[0-9x]+$", var.open_next_version)) == true ? "v2" : "v3"

  scripts = var.scripts

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

  open_next_version = try(coalesce(each.value.open_next_version, var.open_next_version), null)

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
  layers                               = try(coalesce(each.value.layers, var.layers), null)
  origin_timeouts                      = try(coalesce(each.value.origin_timeouts, var.origin_timeouts), null)

  warmer_function             = try(coalesce(each.value.warmer_function, var.warmer_function), null)
  server_function             = try(coalesce(each.value.server_function, var.server_function), null)
  image_optimisation_function = try(coalesce(each.value.image_optimisation_function, var.image_optimisation_function), null)
  revalidation_function       = try(coalesce(each.value.revalidation_function, var.revalidation_function), null)
  additional_server_functions = try(coalesce(each.value.additional_server_functions, var.additional_server_functions), null)
  edge_functions              = try(coalesce(each.value.edge_functions, var.edge_functions), null)

  behaviours     = try(coalesce(each.value.behaviours, var.behaviours), null)
  tag_mapping_db = try(coalesce(each.value.tag_mapping_db, var.tag_mapping_db), null)

  website_bucket         = var.deployment != "SHARED_DISTRIBUTION_AND_BUCKET" ? merge(try(coalesce(each.value.website_bucket, var.website_bucket), {}), { deployment = "CREATE", create_bucket_policy = var.deployment == "INDEPENDENT_ZONES" }) : { deployment = "NONE", arn = one(aws_s3_bucket.shared_bucket[*].arn), name = one(aws_s3_bucket.shared_bucket[*].id), region = data.aws_region.current.name, domain_name = one(aws_s3_bucket.shared_bucket[*].bucket_regional_domain_name) }
  distribution           = var.deployment == "INDEPENDENT_ZONES" ? try(coalesce(each.value.distribution, var.distribution), {}) : { deployment = "NONE", enabled = null, ipv6_enabled = null, http_version = null, price_class = null, geo_restrictions = null, x_forwarded_host_function = null, auth_function = null, lambda_url_oac = null, cache_policy = null }
  waf                    = try(coalesce(each.value.waf, var.waf), null)
  domain_config          = try(coalesce(each.value.domain_config, var.domain_config), null)
  continuous_deployment  = coalesce(each.value.continuous_deployment, var.continuous_deployment)
  custom_error_responses = var.deployment == "INDEPENDENT_ZONES" ? try(coalesce(each.value.custom_error_responses, var.custom_error_responses), []) : each.value.root == true ? var.custom_error_responses : []

  scripts = var.scripts

  providers = {
    aws.global          = aws.global
    aws.dns             = aws.dns
    aws.iam             = aws.iam
    aws.server_function = aws.server_function
  }
}

# Moved to the multi-zone to prevent a cyclic dependency

resource "aws_lambda_permission" "function_url_permission" {
  for_each = local.function_url_permission_details

  action                 = "lambda:InvokeFunctionUrl"
  function_name          = each.value.function_name
  principal              = "cloudfront.amazonaws.com"
  source_arn             = each.value.distribution_name == "production" ? one(module.public_resources[*].arn) : one(module.public_resources[*].staging_arn)
  qualifier              = each.value.alias
  function_url_auth_type = "AWS_IAM"
}

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
