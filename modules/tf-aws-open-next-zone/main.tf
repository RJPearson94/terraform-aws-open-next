locals {
  should_create_isr_tag_mapping = var.tag_mapping_db.deployment == "CREATE"
  isr_tag_mapping_file_path     = "${var.folder_path}/dynamodb-provider/dynamodb-cache.json"
  isr_tag_mapping               = local.should_create_isr_tag_mapping && fileexists(local.isr_tag_mapping_file_path) ? jsondecode(file(local.isr_tag_mapping_file_path)) : []
  isr_tag_mapping_with_tf_key   = [for tag_mapping in local.isr_tag_mapping : merge(tag_mapping, { tf_key = length([for isr_tag_mapping in local.isr_tag_mapping : isr_tag_mapping if isr_tag_mapping.tag.S == tag_mapping.tag.S]) > 1 ? "${tag_mapping.tag.S}-${tag_mapping.path.S}" : tag_mapping.tag.S })]
  isr_tag_mapping_db_name       = local.should_create_isr_tag_mapping ? one(aws_dynamodb_table.isr_table[*].name) : null
  isr_tag_mapping_db_arn        = local.should_create_isr_tag_mapping ? one(aws_dynamodb_table.isr_table[*].arn) : null

  should_create_website_bucket = var.website_bucket.deployment == "CREATE"
  website_bucket_arn           = local.should_create_website_bucket ? one(aws_s3_bucket.bucket[*].arn) : var.website_bucket.arn
  website_bucket_name          = local.should_create_website_bucket ? one(aws_s3_bucket.bucket[*].id) : var.website_bucket.name
  website_bucket_region        = local.should_create_website_bucket ? data.aws_region.current.name : var.website_bucket.region
  website_bucket_domain_name   = local.should_create_website_bucket ? one(aws_s3_bucket.bucket[*].bucket_regional_domain_name) : var.website_bucket.domain_name

  open_next_versions = {
    v2 = can(regex("^v2\\.[0-9x]+\\.[0-9x]+$", var.open_next_version)),
    v3 = can(regex("^v3\\.[0-9x]+\\.[0-9x]+$", var.open_next_version)),
  }
  open_next_output_path         = "${var.folder_path}/open-next.output.json"
  open_next_path_without_folder = endswith(var.folder_path, ".open-next") ? replace(var.folder_path, "/.open-next", "") : var.folder_path
  open_next_config              = local.open_next_versions.v2 == false && fileexists(local.open_next_output_path) ? jsondecode(file(local.open_next_output_path)) : { edgeFunctions = null, origins = null, behaviors = null, additionalProps = null }

  open_next_default_server     = local.open_next_versions.v2 ? "${local.open_next_path_without_folder}/.open-next/server-function" : "${local.open_next_path_without_folder}/${lookup(local.origins, "default", { "bundle" = ".open-next/server-functions/default" }).bundle}"
  open_next_image_optimisation = local.open_next_versions.v2 ? "${local.open_next_path_without_folder}/.open-next/image-optimization-function" : "${local.open_next_path_without_folder}/${lookup(local.origins, "imageOptimizer", { "bundle" = ".open-next/image-optimization-function" }).bundle}"
  open_next_revalidation       = local.open_next_versions.v2 ? "${local.open_next_path_without_folder}/.open-next/revalidation-function" : "${local.open_next_path_without_folder}/${lookup(local.additional_props, "revalidationFunction", { "bundle" = ".open-next/revalidation-function" }).bundle}"
  open_next_warmer             = local.open_next_versions.v2 ? "${local.open_next_path_without_folder}/.open-next/warmer-function" : "${local.open_next_path_without_folder}/${lookup(local.additional_props, "warmer", { "bundle" = ".open-next/warmer-function" }).bundle}"

  edge_functions   = merge(lookup(local.open_next_config, "edgeFunctions", null), {})
  origins          = merge(lookup(local.open_next_config, "origins", null), {})
  additional_props = merge(lookup(local.open_next_config, "additionalProps", null), {})
  behaviors        = lookup(local.open_next_config, "behaviors", null) != null ? local.open_next_config["behaviors"] : []

  default_server_function     = local.origins != null ? lookup(local.origins, "default", {}) : {}
  image_optimisation_function = local.origins != null ? lookup(local.origins, "imageOptimizer", {}) : {}
  additional_server_functions = local.origins != null ? { for name, details in local.origins : name => details if contains(["s3", "imageOptimizer", "default"], name) == false } : {}

  create_distribution = var.distribution.deployment == "CREATE"

  staging_alias    = var.aliases != null ? var.aliases.staging : one(module.open_next_aliases[*].alias_details.staging)
  production_alias = var.aliases != null ? var.aliases.production : one(module.open_next_aliases[*].alias_details.production)
  aliases          = var.aliases != null ? distinct(values(var.aliases)) : one(module.open_next_aliases[*].alias_details.aliases)

  edge_function_env_variables = { "OPEN_NEXT_ORIGIN" = jsonencode(merge({ for name, details in local.additional_server_functions : name => { "host" : lookup(module.additional_server_function[name].url_hostnames, local.staging_alias, null), "protocol" : "https", "port" : 443 } }, { "default" = { "host" : lookup(module.server_function.url_hostnames, local.staging_alias, null), "protocol" : "https", "port" : 443 } })) }

  prefix = var.prefix == null ? "" : "${var.prefix}-"
  suffix = var.suffix == null ? "" : "-${var.suffix}"

  auth_options = {
    "REGIONAL_LAMBDA_WITH_OAC"                   = "OAC",
    "REGIONAL_LAMBDA_WITH_OAC_AND_ANY_PRINCIPAL" = "OAC",
    "REGIONAL_LAMBDA_WITH_AUTH_LAMBDA"           = "AUTH_LAMBDA"
  }

  lambda_permissions = local.create_distribution ? merge([for distribution in try(one(module.public_resources[*].distributions_provisioned), []) : { for alias in local.aliases : "${distribution}-${alias}" => { distribution = distribution, alias = alias } }]...) : {}

  zone_origins = merge({
    static_assets = {
      domain_name  = local.website_bucket_domain_name
      backend_name = "website-bucket"
      arn          = null
      path         = "/${module.s3_assets.origin_asset_path}"
      auth         = null
      headers      = null
    }
    image_optimisation = {
      domain_name  = var.image_optimisation_function.create ? one(module.image_optimisation_function[*].url_hostnames)[local.staging_alias] : null
      backend_name = var.image_optimisation_function.create ? one(module.image_optimisation_function[*].name) : null
      arn          = var.image_optimisation_function.create ? one(module.image_optimisation_function[*].arn) : null
      path         = null
      auth         = lookup(local.auth_options, var.image_optimisation_function.backend_deployment_type, null)
      headers      = null
    }
    },
    local.server_at_edge ? {} : { server = {
      domain_name  = lookup(module.server_function.url_hostnames, local.staging_alias, null)
      backend_name = module.server_function.name
      arn          = module.server_function.arn
      path         = null
      auth         = lookup(local.auth_options, var.server_function.backend_deployment_type, null)
      headers      = null
    } },
    { for name, additional_server_function in local.additional_server_functions : name => {
      domain_name  = lookup(module.additional_server_function[name].url_hostnames, local.staging_alias, null)
      backend_name = module.additional_server_function[name].name
      arn          = module.additional_server_function[name].arn
      path         = null
      auth         = lookup(local.auth_options, try(var.additional_server_functions.function_overrides[name].backend_deployment_type, var.additional_server_functions.backend_deployment_type), null)
      headers      = null
    } if try(var.additional_server_functions.function_overrides[name].backend_deployment_type, var.additional_server_functions.backend_deployment_type) != "EDGE_LAMBDA" }
  )
  zone = {
    reinvalidation_hash = sha1(join("-", concat(module.s3_assets.file_hashes, [try(module.server_function.version, "")], [for edge_function in module.edge_function : edge_function.version], [for additional_server_function in module.additional_server_function : additional_server_function.version])))
    origins             = local.zone_origins
    origin_names        = keys(local.zone_origins)
  }

  user_supplied_behaviours = coalesce(var.behaviours, { custom_error_responses = null, static_assets = null, server = null, image_optimisation = null, additional_origins = {} })
  zone_behaviours = merge(local.user_supplied_behaviours, {
    static_assets = merge(coalesce(local.user_supplied_behaviours.static_assets, { paths = null, additional_paths = null, path_overrides = null, allowed_methods = null, cached_methods = null, cache_policy_id = null, origin_request_policy_id = null, compress = null, viewer_protocol_policy = null, viewer_request = null, viewer_response = null, origin_request = null, origin_response = null }), {
      paths            = try(coalesce(try(local.user_supplied_behaviours.static_assets.paths, null), local.open_next_versions.v2 ? null : [for behavior in local.behaviors : behavior.pattern == "*" || startswith(behavior.pattern, "/") ? behavior.pattern : "/${behavior.pattern}" if behavior.origin == "s3"]), null)
      additional_paths = try(coalesce(try(local.user_supplied_behaviours.static_assets.additional_paths, null), module.s3_assets.cloudfront_asset_mappings), [])
    })
    server = merge(coalesce(local.user_supplied_behaviours.server, { paths = null, path_overrides = null, allowed_methods = null, cached_methods = null, cache_policy_id = null, origin_request_policy_id = null, compress = null, viewer_protocol_policy = null, viewer_request = null, viewer_response = null, origin_request = null, origin_response = null }), {
      paths = try(coalesce(try(local.user_supplied_behaviours.server.paths, null), local.open_next_versions.v2 ? null : [for behavior in local.behaviors : behavior.pattern == "*" || startswith(behavior.pattern, "/") ? behavior.pattern : "/${behavior.pattern}" if behavior.origin == "default"]), null)
      origin_request = local.server_at_edge ? {
        arn          = module.server_function.qualified_arn
        include_body = true
      } : null
      path_overrides = merge(try(local.user_supplied_behaviours.server.path_overrides, {}), { for behavior in local.behaviors : behavior.pattern == "*" || startswith(behavior.pattern, "/") ? behavior.pattern : "/${behavior.pattern}" => { origin_request = { arn = module.edge_function[behavior["edgeFunction"]].qualified_arn, include_body = true } } if behavior.origin == "default" && lookup(behavior, "edgeFunction", null) != null })
    })
    image_optimisation = merge(coalesce(local.user_supplied_behaviours.image_optimisation, { paths = null, path_overrides = null, allowed_methods = null, cached_methods = null, cache_policy_id = null, origin_request_policy_id = null, compress = null, viewer_protocol_policy = null, viewer_request = null, viewer_response = null, origin_request = null, origin_response = null }), {
      paths = try(coalesce(try(local.user_supplied_behaviours.image_optimisation.paths, null), local.open_next_versions.v2 ? null : [for behavior in local.behaviors : behavior.pattern == "*" || startswith(behavior.pattern, "/") ? behavior.pattern : "/${behavior.pattern}" if behavior.origin == "imageOptimizer"]), null)
    })
    additional_origins = { for name, additional_server_function in local.additional_server_functions : name => merge(coalesce(local.user_supplied_behaviours.additional_origins, { paths = null, path_overrides = null, allowed_methods = null, cached_methods = null, cache_policy_id = null, origin_request_policy_id = null, compress = null, viewer_protocol_policy = null, viewer_request = null, viewer_response = null, origin_request = null, origin_response = null, origin_reference = null }), {
      paths          = try(coalesce(try(local.user_supplied_behaviours.additional_origins[name].paths, null), local.open_next_versions.v2 ? null : [for behavior in local.behaviors : behavior.pattern == "*" || startswith(behavior.pattern, "/") ? behavior.pattern : "/${behavior.pattern}" if behavior.origin == name]), null)
      origin_request = try(local.user_supplied_behaviours.additional_origins[name].origin_request, null)
      path_overrides = merge(try(local.user_supplied_behaviours.additional_origins[name].path_overrides, {}), { for behavior in local.behaviors : behavior.pattern == "*" || startswith(behavior.pattern, "/") ? behavior.pattern : "/${behavior.pattern}" => { origin_request = { arn = module.edge_function[behavior["edgeFunction"]].qualified_arn, include_body = true } } if behavior.origin == name && lookup(behavior, "edgeFunction", null) != null })
    }) }
  })

  // This is still needed for open next v2 support
  server_at_edge = var.server_function.backend_deployment_type == "EDGE_LAMBDA"

  cache_bucket_env_variables = {
    "CACHE_BUCKET_NAME" : local.website_bucket_name,
    "CACHE_BUCKET_REGION" : local.website_bucket_region,
    "CACHE_BUCKET_KEY_PREFIX" : module.s3_assets.cache_key_prefix
  }
  revalidation_queue_env_variables = {
    "REVALIDATION_QUEUE_URL" : aws_sqs_queue.revalidation_queue.url,
    "REVALIDATION_QUEUE_REGION" : data.aws_region.current.name,
  }
  tag_mapping_env_variables = local.isr_tag_mapping_db_name != null ? { "CACHE_DYNAMO_TABLE" : local.isr_tag_mapping_db_name } : {}
  server_function_env_variables = merge(
    local.cache_bucket_env_variables,
    local.revalidation_queue_env_variables,
    local.tag_mapping_env_variables,
    var.server_function.additional_environment_variables
  )

  cache_bucket_iam_policies = [{
    "Action" : [
      "s3:GetObject*",
      "s3:GetBucket*",
      "s3:List*",
      "s3:DeleteObject*",
      "s3:PutObject",
      "s3:PutObjectLegalHold",
      "s3:PutObjectRetention",
      "s3:PutObjectTagging",
      "s3:PutObjectVersionTagging",
      "s3:Abort*"
    ],
    "Resource" : [
      local.website_bucket_arn,
      "${local.website_bucket_arn}/*"
    ],
    "Effect" : "Allow"
  }]

  revalidation_queue_iam_policies = [{
    "Action" : [
      "sqs:SendMessage",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
    ],
    "Resource" : aws_sqs_queue.revalidation_queue.arn,
    "Effect" : "Allow"
  }]
  tag_mapping_iam_policies = [{
    "Action" : [
      "dynamodb:BatchGetItem",
      "dynamodb:GetRecords",
      "dynamodb:GetShardIterator",
      "dynamodb:Query",
      "dynamodb:GetItem",
      "dynamodb:Scan",
      "dynamodb:ConditionCheckItem",
      "dynamodb:BatchWriteItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:DescribeTable",
    ],
    "Resource" : [
      local.isr_tag_mapping_db_arn,
      "${local.isr_tag_mapping_db_arn}/index/*"
    ],
    "Effect" : "Allow"
  }]

  custom_error_responses = [for custom_error_response in var.custom_error_responses : {
    bucket_domain_name    = local.zone_origins["static_assets"].domain_name
    error_code            = custom_error_response.error_code
    error_caching_min_ttl = custom_error_response.error_caching_min_ttl
    response_code         = custom_error_response.response_code
    response_page = custom_error_response.response_page != null ? {
      name        = "${custom_error_response.error_code}.html"
      behaviour   = custom_error_response.response_page.path_prefix
      folder_path = "${local.staging_alias}/custom"
    } : null
  }]

  log_groups = { for name, log_group in merge(concat([{ default_server = try(var.server_function.cloudwatch_log, null) }, { warmer = try(var.warmer_function.cloudwatch_log, null) }, { image_optimisation = try(var.image_optimisation_function.cloudwatch_log, null) }, { revalidation = try(var.revalidation_function.cloudwatch_log, null) }], [for name in keys(local.additional_server_functions) : { "${name}" = try(var.additional_server_functions.function_overrides[name].cloudwatch_log, var.additional_server_functions.cloudwatch_log, null) }])...) : name => try(coalesce(log_group, var.cloudwatch_log), null) }
}

module "public_resources" {
  count  = local.create_distribution ? 1 : 0
  source = "../tf-aws-open-next-public-resources"

  zones = [merge({
    root = true
    name = "website"
  }, local.zone)]

  prefix = var.prefix
  suffix = var.suffix

  enabled                   = var.distribution.enabled
  ipv6_enabled              = var.distribution.ipv6_enabled
  http_version              = var.distribution.http_version
  price_class               = var.distribution.price_class
  geo_restrictions          = var.distribution.geo_restrictions
  x_forwarded_host_function = var.distribution.x_forwarded_host_function
  auth_function             = var.distribution.auth_function
  lambda_url_oac            = var.distribution.lambda_url_oac
  cache_policy              = var.distribution.cache_policy

  behaviours            = local.zone_behaviours
  waf                   = var.waf
  domain_config         = var.domain_config
  continuous_deployment = var.continuous_deployment

  custom_error_responses = local.custom_error_responses

  open_next_version_alias = local.open_next_versions.v2 == true ? "v2" : "v3"

  scripts = var.scripts
  providers = {
    aws     = aws.global
    aws.dns = aws.dns
    aws.iam = aws.iam
  }
}

# Config

module "open_next_aliases" {
  count  = var.aliases == null ? 1 : 0
  source = "../tf-aws-open-next-aliases"

  continuous_deployment_strategy = var.continuous_deployment.deployment
  use_continuous_deployment      = var.continuous_deployment.use

  prefix = var.prefix
  suffix = var.suffix
}

resource "terraform_data" "update_aliases" {
  count            = var.aliases == null ? 1 : 0
  triggers_replace = [var.continuous_deployment.deployment, try(one(module.public_resources[*].etag), null)]

  provisioner "local-exec" {
    command = "${coalesce(try(var.scripts.update_parameter_script.interpreter, var.scripts.interpreter, null), "/bin/bash")} ${try(var.scripts.update_parameter_script.path, "${path.module}/scripts/update-parameter.sh")}"

    environment = merge({
      "PARAMETER_NAME" = one(module.open_next_aliases[*].parameter_name)
      "VALUE"          = jsonencode(one(module.open_next_aliases[*].updated_alias_mapping))
    }, try(var.scripts.additional_environment_variables, {}), try(var.scripts.update_parameter_script.additional_environment_variables, {}))
  }
}

# S3

resource "aws_s3_bucket" "bucket" {
  count         = local.should_create_website_bucket ? 1 : 0
  bucket        = "${local.prefix}website-bucket${local.suffix}"
  force_destroy = var.website_bucket.force_destroy
}

resource "aws_s3_bucket_policy" "bucket_policy" {
  count = local.should_create_website_bucket && var.website_bucket.create_bucket_policy == true && local.create_distribution ? 1 : 0

  bucket = one(aws_s3_bucket.bucket[*].id)
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
        "Resource" : "${one(aws_s3_bucket.bucket[*].arn)}/*",
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

module "s3_assets" {
  source = "../tf-aws-open-next-s3-assets"

  bucket_name = local.website_bucket_name

  folder_path                          = var.folder_path
  s3_exclusion_regex                   = var.s3_exclusion_regex
  cache_control_immutable_assets_regex = var.cache_control_immutable_assets_regex
  content_types                        = var.content_types

  force_destroy = var.website_bucket.force_destroy
  remove_folder = var.continuous_deployment.use && var.continuous_deployment.deployment != "NONE"

  additional_files = [for custom_error_response in var.custom_error_responses : merge(custom_error_response.response_page, { name = "${custom_error_response.error_code}.html", s3_path_prefix = local.staging_alias }) if custom_error_response.response_page != null]

  s3_path_prefix = join("/", compact([var.s3_folder_prefix, local.staging_alias]))
  zone_suffix    = var.zone_suffix

  scripts = var.scripts
}

# Edge Functions

# As lambda@edge does not support environment variables, the module will injected them at the top of the server code prior to the code being uploaded to AWS, credit to SST for the inspiration behind this. https://github.com/sst/sst/blob/3b792053d90c49d9ca693308646a3389babe9ceb/packages/sst/src/constructs/EdgeFunction.ts#L193
resource "local_file" "edge_functions_modifications" {
  for_each = { for name, edge_function in local.edge_functions : name => edge_function if try(var.edge_functions.function_overrides[name].function_code.zip, null) == null && try(var.edge_functions.function_overrides[name].function_code.s3, null) == null }

  content  = "process.env = { ...process.env, ...${jsonencode(merge(try(coalesce(try(var.edge_functions.function_overrides[each.key].include_open_next_origin_env_variable, null), var.edge_functions.include_open_next_origin_env_variable), true) == true ? local.edge_function_env_variables : {}, try(coalesce(try(var.edge_functions.function_overrides[each.key].additional_environment_variables, null), var.edge_functions.additional_environment_variables), {})))} };\r\n${file("${local.open_next_path_without_folder}/${each.value.bundle}/handler.mjs")}"
  filename = "${local.open_next_path_without_folder}/${each.value.bundle}/handler.mjs"
}

module "edge_function" {
  for_each = local.edge_functions
  source   = "../tf-aws-lambda"

  function_name = each.key
  function_code = {
    zip = try(var.edge_functions.function_overrides[each.key].function_code.s3, null) == null ? coalesce(try(var.edge_functions.function_overrides[each.key].function_code.zip, null), {
      path = data.archive_file.edge_function[each.key].output_path
      hash = data.archive_file.edge_function[each.key].output_base64sha256
    }) : null
    s3 = try(var.edge_functions.function_overrides[each.key].function_code.s3, null)
  }

  run_at_edge = true
  runtime     = try(coalesce(try(var.edge_functions.function_overrides[each.key].runtime, null), try(var.edge_functions.runtime, null)), null)
  handler     = try(coalesce(try(var.edge_functions.function_overrides[each.key].handler, null), try(var.edge_functions.handler, null)), "handler.handler")

  memory_size = try(coalesce(try(var.edge_functions.function_overrides[each.key].memory_size, null), try(var.edge_functions.memory_size, null)), null)
  timeout     = try(coalesce(try(var.edge_functions.function_overrides[each.key].timeout, null), try(var.edge_functions.timeout, null)), null)

  additional_iam_policies = try(coalesce(try(var.edge_functions.function_overrides[each.key].additional_iam_policies, null), try(var.edge_functions.additional_iam_policies, null)), [])
  iam                     = try(coalesce(try(var.edge_functions.function_overrides[each.key].iam, null), try(var.edge_functions.iam, null), var.iam), null)

  prefix = var.prefix
  suffix = var.suffix

  scripts  = var.scripts
  timeouts = try(coalesce(try(var.edge_functions.function_overrides[each.key].timeouts, null), try(var.edge_functions.timeouts, null), null), null)

  providers = {
    aws     = aws.global
    aws.iam = aws.iam
  }
}

# Default Server Function

# As lambda@edge does not support environment variables, the module will injected them at the top of the server code prior to the code being uploaded to AWS, credit to SST for the inspiration behind this. https://github.com/sst/sst/blob/3b792053d90c49d9ca693308646a3389babe9ceb/packages/sst/src/constructs/EdgeFunction.ts#L193
resource "local_file" "lambda_at_edge_modifications" {
  count = local.server_at_edge && try(var.server_function.function_code.zip, null) == null && try(var.server_function.function_code.s3, null) == null ? 1 : 0

  content  = "process.env = { ...process.env, ...${jsonencode(local.server_function_env_variables)} };\r\n${file("${local.open_next_default_server}/index.mjs")}"
  filename = "${local.open_next_default_server}/index.mjs"

  lifecycle {
    precondition {
      condition     = local.open_next_versions.v2 == true
      error_message = "EDGE_LAMBDA backend deployment type is only supported with open next v2"
    }
  }
}

module "server_function" {
  source = "../tf-aws-lambda"

  function_name = "server-function"
  function_code = {
    zip = try(var.server_function.function_code.s3, null) == null ? coalesce(try(var.server_function.function_code.zip, null), {
      path = one(data.archive_file.server_function[*].output_path)
      hash = one(data.archive_file.server_function[*].output_base64sha256)
    }) : null
    s3 = try(var.server_function.function_code.s3, null)
  }

  runtime = var.server_function.runtime
  handler = try(var.server_function.function_code.handler, "index.handler")

  memory_size = var.server_function.memory_size
  timeout     = var.server_function.timeout

  additional_iam_policies = var.server_function.additional_iam_policies
  iam_policy_statements = concat(
    local.cache_bucket_iam_policies,
    local.revalidation_queue_iam_policies,
    local.tag_mapping_iam_policies
  )

  environment_variables = local.server_at_edge ? {} : local.server_function_env_variables

  architecture   = try(coalesce(var.server_function.function_architecture, var.function_architecture), "x86_64")
  cloudwatch_log = local.log_groups["default_server"] != null ? merge(local.log_groups["default_server"], local.log_groups["default_server"].deployment == "SHARED_PER_ZONE" ? { deployment = "USE_EXISTING", name = one(aws_cloudwatch_log_group.log_group[*].name) } : {}) : null
  iam            = try(coalesce(var.server_function.iam, var.iam), null)
  vpc            = try(coalesce(var.server_function.vpc, var.vpc), null)

  prefix = var.prefix
  suffix = var.suffix

  aliases = {
    create          = true
    names           = local.aliases
    alias_to_update = local.staging_alias
  }

  run_at_edge = local.server_at_edge

  function_url = {
    create              = local.server_at_edge == false
    authorization_type  = try(contains(["OAC", "AUTH_LAMBDA"], lookup(local.auth_options, var.server_function.backend_deployment_type, null)), false) ? "AWS_IAM" : "NONE"
    allow_any_principal = var.server_function.backend_deployment_type != "REGIONAL_LAMBDA_WITH_OAC"
    enable_streaming    = coalesce(var.server_function.enable_streaming, lookup(local.default_server_function, "streaming", false))
  }

  scripts  = var.scripts
  timeouts = var.server_function.timeouts

  providers = {
    aws     = aws.server_function
    aws.iam = aws.iam
  }
}

resource "aws_lambda_permission" "server_function_url_permission" {
  for_each = try(local.zone_origins["server"].auth, null) == "OAC" ? local.lambda_permissions : {}

  action                 = "lambda:InvokeFunctionUrl"
  function_name          = module.server_function.name
  principal              = "cloudfront.amazonaws.com"
  source_arn             = each.value.distribution == "production" ? one(module.public_resources[*].arn) : one(module.public_resources[*].staging_arn)
  qualifier              = each.value.alias
  function_url_auth_type = "AWS_IAM"
}

module "additional_server_function" {
  for_each = local.additional_server_functions
  source   = "../tf-aws-lambda"

  function_name = each.key

  function_code = {
    zip = try(var.additional_server_functions.function_overrides[each.key].function_code.s3, null) == null ? coalesce(try(var.additional_server_functions.function_overrides[each.key].function_code.zip, null), {
      path = data.archive_file.additional_server_function[each.key].output_path
      hash = data.archive_file.additional_server_function[each.key].output_base64sha256
    }) : null
    s3 = try(var.additional_server_functions.function_overrides[each.key].function_code.s3, null)
  }

  runtime = try(var.additional_server_functions.function_overrides[each.key].runtime, var.additional_server_functions.runtime)
  handler = try(coalesce(try(var.additional_server_functions.function_overrides[each.key].handler, null), try(var.additional_server_functions.handler, null)), "index.handler")

  memory_size = try(var.additional_server_functions.function_overrides[each.key].memory_size, var.additional_server_functions.memory_size)
  timeout     = try(var.additional_server_functions.function_overrides[each.key].timeout, var.additional_server_functions.timeout)

  additional_iam_policies = try(coalesce(try(var.additional_server_functions.function_overrides[each.key].additional_iam_policies, null), try(var.additional_server_functions.additional_iam_policies, null)), [])
  iam_policy_statements = concat(
    try(coalesce(try(var.additional_server_functions.function_overrides[each.key].iam_policies.include_bucket_access, null), try(var.additional_server_functions.iam_policies.include_bucket_access, null)), false) == true ? local.cache_bucket_iam_policies : [],
    try(coalesce(try(var.additional_server_functions.function_overrides[each.key].iam_policies.include_revalidation_queue_access, null), try(var.additional_server_functions.iam_policies.include_revalidation_queue_access, null)), false) == true ? local.revalidation_queue_iam_policies : [],
    try(coalesce(try(var.additional_server_functions.function_overrides[each.key].iam_policies.include_tag_mapping_db_access, null), try(var.additional_server_functions.iam_policies.include_tag_mapping_db_access, null)), false) == true ? local.tag_mapping_iam_policies : []
  )

  environment_variables = try(var.additional_server_functions.function_overrides[each.key].backend_deployment_type, var.additional_server_functions.backend_deployment_type) == "EDGE_LAMBDA" ? {} : merge(
    try(coalesce(try(var.additional_server_functions.function_overrides[each.key].iam_policies.include_bucket_access, null), try(var.additional_server_functions.iam_policies.include_bucket_access, null)), false) == true ? local.cache_bucket_env_variables : {},
    try(coalesce(try(var.additional_server_functions.function_overrides[each.key].iam_policies.include_revalidation_queue_access, null), try(var.additional_server_functions.iam_policies.include_revalidation_queue_access, null)), false) == true ? local.revalidation_queue_env_variables : {},
    try(coalesce(try(var.additional_server_functions.function_overrides[each.key].iam_policies.include_tag_mapping_db_access, null), try(var.additional_server_functions.iam_policies.include_tag_mapping_db_access, null)), false) == true ? local.tag_mapping_env_variables : {},
    try(coalesce(try(var.additional_server_functions.function_overrides[each.key].iam_policies.additional_environment_variables, null), try(var.additional_server_functions.iam_policies.additional_environment_variables, null)), {})
  )

  architecture   = coalesce(try(var.additional_server_functions.function_overrides[each.key].function_architecture, var.additional_server_functions.function_architecture), "x86_64")
  cloudwatch_log = local.log_groups[each.key] != null ? merge(local.log_groups[each.key], local.log_groups[each.key].deployment == "SHARED_PER_ZONE" ? { deployment = "USE_EXISTING", name = one(aws_cloudwatch_log_group.log_group[*].name) } : {}) : null
  iam            = try(var.additional_server_functions.function_overrides[each.key].iam, var.additional_server_functions.iam)
  vpc            = try(var.additional_server_functions.function_overrides[each.key].vpc, var.additional_server_functions.vpc)

  prefix = var.prefix
  suffix = var.suffix

  aliases = {
    create          = true
    names           = local.aliases
    alias_to_update = local.staging_alias
  }

  function_url = {
    create              = true
    authorization_type  = try(contains(["OAC", "AUTH_LAMBDA"], lookup(local.auth_options, try(var.additional_server_functions.function_overrides[each.key].backend_deployment_type, var.additional_server_functions.backend_deployment_type), null)), false) ? "AWS_IAM" : "NONE"
    allow_any_principal = try(var.additional_server_functions.function_overrides[each.key].backend_deployment_type, var.additional_server_functions.backend_deployment_type) != "REGIONAL_LAMBDA_WITH_OAC"
    enable_streaming    = coalesce(try(var.additional_server_functions.function_overrides[each.key].enable_streaming, var.additional_server_functions.enable_streaming, null), try(each.value.streaming, null), false)
  }

  scripts  = var.scripts
  timeouts = try(var.additional_server_functions.function_overrides[each.key].timeouts, var.additional_server_functions.timeouts)

  providers = {
    aws     = aws.server_function
    aws.iam = aws.iam
  }
}

resource "aws_lambda_permission" "additional_server_function_url_permission" {
  for_each = merge([
    for key, additional_server_function in local.additional_server_functions : {
      for lambda_permission_key, lambda_permissions in local.lambda_permissions : "${key}-${lambda_permission_key}" => merge({ name = key }, additional_server_function, lambda_permissions)
    } if try(var.additional_server_functions.function_overrides[key].backend_deployment_type, var.additional_server_functions.backend_deployment_type) != "REGIONAL_LAMBDA_WITH_OAC"
  ]...)

  action                 = "lambda:InvokeFunctionUrl"
  function_name          = module.additional_server_function[each.value.name].name
  principal              = "cloudfront.amazonaws.com"
  source_arn             = each.value.distribution == "production" ? one(module.public_resources[*].arn) : one(module.public_resources[*].staging_arn)
  qualifier              = each.value.alias
  function_url_auth_type = "AWS_IAM"
}

# Warmer Function

module "warmer_function" {
  for_each = toset(try(var.warmer_function.warm_staging.enabled, false) && var.continuous_deployment.deployment != "NONE" ? local.aliases : var.warmer_function.enabled ? [local.production_alias] : [])
  source   = "../tf-aws-lambda"

  function_name = "${each.value}-warmer-function"
  function_code = {
    zip = try(var.warmer_function.function_code.s3, null) == null ? coalesce(try(var.warmer_function.function_code.zip, null), {
      path = one(data.archive_file.warmer_function[*].output_path)
      hash = one(data.archive_file.warmer_function[*].output_base64sha256)
    }) : null
    s3 = try(var.warmer_function.function_code.s3, null)
  }

  runtime = var.warmer_function.runtime
  handler = try(var.warmer_function.function_code.handler, "index.handler")

  memory_size = var.warmer_function.memory_size
  timeout     = var.warmer_function.timeout

  environment_variables = merge(local.open_next_versions.v2 ? {
    "FUNCTION_NAME" : "${module.server_function.name}:${each.value}",
    "CONCURRENCY" : each.value == local.production_alias ? var.warmer_function.concurrency : coalesce(try(var.warmer_function.warm_staging.concurrency, null), var.warmer_function.concurrency)
    } : {
    "WARM_PARAMS" : jsonencode(concat([{
      function    = "${module.server_function.name}:${each.value}",
      concurrency = each.value == local.production_alias ? var.warmer_function.concurrency : coalesce(try(var.warmer_function.warm_staging.concurrency, null), var.warmer_function.concurrency)
      }], [
      for additional_function in module.additional_server_function : {
        function    = "${additional_function.name}:${each.value}",
        concurrency = each.value == local.production_alias ? var.warmer_function.concurrency : coalesce(try(var.warmer_function.warm_staging.concurrency, null), var.warmer_function.concurrency)
      }
      ]
    ))
  }, var.warmer_function.additional_environment_variables)

  additional_iam_policies = var.warmer_function.additional_iam_policies
  iam_policy_statements = [
    {
      "Action" : [
        "lambda:InvokeFunction"
      ],
      "Resource" : concat(
        ["${module.server_function.arn}:${each.value}"],
        [for additional_function in module.additional_server_function : "${additional_function.arn}:${each.value}"]
      )
      "Effect" : "Allow"
    }
  ]

  architecture   = try(coalesce(var.warmer_function.function_architecture, var.function_architecture), null)
  cloudwatch_log = local.log_groups["warmer"] != null ? merge(local.log_groups["warmer"], local.log_groups["warmer"].deployment == "SHARED_PER_ZONE" ? { deployment = "USE_EXISTING", name = one(aws_cloudwatch_log_group.log_group[*].name) } : {}) : null
  iam            = try(coalesce(var.warmer_function.iam, var.iam), null)
  vpc            = try(coalesce(var.warmer_function.vpc, var.vpc), null)

  prefix = var.prefix
  suffix = var.suffix

  function_url = {
    create = false
  }

  schedule = var.warmer_function.schedule
  timeouts = var.warmer_function.timeouts

  scripts = var.scripts

  providers = {
    aws.iam = aws.iam
  }
}

# Image Optimisation Function

module "image_optimisation_function" {
  count  = var.image_optimisation_function.create ? 1 : 0
  source = "../tf-aws-lambda"

  function_name = "image-optimization-function"
  function_code = {
    zip = try(var.image_optimisation_function.function_code.s3, null) == null ? coalesce(try(var.image_optimisation_function.function_code.zip, null), {
      path = one(data.archive_file.image_optimisation_function[*].output_path)
      hash = one(data.archive_file.image_optimisation_function[*].output_base64sha256)
    }) : null
    s3 = try(var.image_optimisation_function.function_code.s3, null)
  }

  runtime = var.image_optimisation_function.runtime
  handler = try(var.image_optimisation_function.function_code.handler, "index.handler")

  memory_size = var.image_optimisation_function.memory_size
  timeout     = var.image_optimisation_function.timeout

  environment_variables = merge({
    "BUCKET_NAME"       = local.website_bucket_name,
    "BUCKET_KEY_PREFIX" = module.s3_assets.asset_key_prefix
    },
    try(var.image_optimisation_function.static_image_optimisation, false) == true ? {
      "OPENNEXT_STATIC_ETAG" = "true"
    } : {},
  var.image_optimisation_function.additional_environment_variables)

  additional_iam_policies = var.image_optimisation_function.additional_iam_policies
  iam_policy_statements = [
    {
      "Action" : [
        "s3:GetObject"
      ],
      "Resource" : "${local.website_bucket_arn}/*",
      "Effect" : "Allow"
    }
  ]

  architecture   = try(coalesce(var.image_optimisation_function.function_architecture, var.function_architecture), null)
  cloudwatch_log = local.log_groups["image_optimisation"] != null ? merge(local.log_groups["image_optimisation"], local.log_groups["image_optimisation"].deployment == "SHARED_PER_ZONE" ? { deployment = "USE_EXISTING", name = one(aws_cloudwatch_log_group.log_group[*].name) } : {}) : null
  iam            = try(coalesce(var.image_optimisation_function.iam, var.iam), null)
  vpc            = try(coalesce(var.image_optimisation_function.vpc, var.vpc), null)

  prefix = var.prefix
  suffix = var.suffix

  function_url = {
    create              = true
    authorization_type  = try(contains(["OAC", "AUTH_LAMBDA"], lookup(local.auth_options, var.image_optimisation_function.backend_deployment_type, null)), false) ? "AWS_IAM" : "NONE"
    allow_any_principal = var.image_optimisation_function.backend_deployment_type != "REGIONAL_LAMBDA_WITH_OAC"
  }

  aliases = {
    create          = true
    names           = local.aliases
    alias_to_update = local.staging_alias
  }

  timeouts = var.image_optimisation_function.timeouts

  scripts = var.scripts

  providers = {
    aws.iam = aws.iam
  }
}

resource "aws_lambda_permission" "image_optimisation_function_url_permission" {
  for_each = var.image_optimisation_function.create && lookup(local.auth_options, var.image_optimisation_function.backend_deployment_type, null) == "OAC" ? local.lambda_permissions : {}

  action                 = "lambda:InvokeFunctionUrl"
  function_name          = one(module.image_optimisation_function[*].name)
  principal              = "cloudfront.amazonaws.com"
  source_arn             = each.value.distribution == "production" ? one(module.public_resources[*].arn) : one(module.public_resources[*].staging_arn)
  qualifier              = each.value.alias
  function_url_auth_type = "AWS_IAM"
}

# Revalidation Function

module "revalidation_function" {
  source = "../tf-aws-lambda"

  function_name = "revalidation-function"
  function_code = {
    zip = try(var.revalidation_function.function_code.s3, null) == null ? coalesce(try(var.revalidation_function.function_code.zip, null), {
      path = one(data.archive_file.revalidation_function[*].output_path)
      hash = one(data.archive_file.revalidation_function[*].output_base64sha256)
    }) : null
    s3 = try(var.revalidation_function.function_code.s3, null)
  }

  runtime = var.revalidation_function.runtime
  handler = try(var.revalidation_function.function_code.handler, "index.handler")

  memory_size = var.revalidation_function.memory_size
  timeout     = var.revalidation_function.timeout

  environment_variables = var.revalidation_function.additional_environment_variables

  additional_iam_policies = var.revalidation_function.additional_iam_policies
  iam_policy_statements = [
    {
      "Action" : [
        "sqs:ReceiveMessage",
        "sqs:ChangeMessageVisibility",
        "sqs:GetQueueUrl",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes"
      ],
      "Resource" : aws_sqs_queue.revalidation_queue.arn,
      "Effect" : "Allow"
    }
  ]

  architecture   = try(coalesce(var.revalidation_function.function_architecture, var.function_architecture), null)
  cloudwatch_log = local.log_groups["revalidation"] != null ? merge(local.log_groups["revalidation"], local.log_groups["revalidation"].deployment == "SHARED_PER_ZONE" ? { deployment = "USE_EXISTING", name = one(aws_cloudwatch_log_group.log_group[*].name) } : {}) : null
  iam            = try(coalesce(var.revalidation_function.iam, var.iam), null)
  vpc            = try(coalesce(var.revalidation_function.vpc, var.vpc), null)

  prefix = var.prefix
  suffix = var.suffix

  scripts = var.scripts

  providers = {
    aws.iam = aws.iam
  }
}

# SQS

resource "aws_sqs_queue" "revalidation_queue" {
  name                        = "${local.prefix}isr-queue${local.suffix}.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
}

resource "aws_lambda_event_source_mapping" "revalidation_queue_source" {
  event_source_arn = aws_sqs_queue.revalidation_queue.arn
  function_name    = module.revalidation_function.arn
}

# DynamoDB

resource "aws_dynamodb_table" "isr_table" {
  count = local.should_create_isr_tag_mapping ? 1 : 0
  name  = "${local.prefix}isr-tag-mapping${local.suffix}"

  billing_mode   = var.tag_mapping_db.billing_mode
  read_capacity  = var.tag_mapping_db.read_capacity
  write_capacity = var.tag_mapping_db.write_capacity

  hash_key  = "tag"
  range_key = "path"

  attribute {
    name = "tag"
    type = "S"
  }

  attribute {
    name = "path"
    type = "S"
  }

  attribute {
    name = "revalidatedAt"
    type = "N"
  }

  global_secondary_index {
    name            = "revalidate"
    hash_key        = "path"
    range_key       = "revalidatedAt"
    projection_type = "ALL"
    read_capacity   = try(coalesce(var.tag_mapping_db.revalidate_gsi.read_capacity, var.tag_mapping_db.read_capacity), null)
    write_capacity  = try(coalesce(var.tag_mapping_db.revalidate_gsi.write_capacity, var.tag_mapping_db.write_capacity), null)
  }
}

resource "terraform_data" "isr_table_item" {
  for_each = { for item in local.isr_tag_mapping_with_tf_key : item.tf_key => item }

  triggers_replace = [local.staging_alias, md5(jsonencode(each.value))]

  provisioner "local-exec" {
    command = "${coalesce(try(var.scripts.save_item_to_dynamo_script.interpreter, var.scripts.interpreter, null), "/bin/bash")} ${try(var.scripts.save_item_to_dynamo_script.path, "${path.module}/scripts/save-item-to-dynamo.sh")}"

    environment = merge({
      "TABLE_NAME" = local.isr_tag_mapping_db_name
      "ITEM"       = jsonencode(merge({ for name, value in each.value : name => value if name != "tf_key" }, { alias = { "S" = local.staging_alias } }))
    }, try(var.scripts.additional_environment_variables, {}), try(var.scripts.save_item_to_dynamo_script.additional_environment_variables, {}))
  }
}

# Cloudwatch Logs

resource "aws_cloudwatch_log_group" "log_group" {
  count = contains([for log_group in values(local.log_groups) : try(log_group.deployment, "PER_FUNCTION")], "SHARED_PER_ZONE") ? 1 : 0

  name              = "/aws/lambda/${local.prefix}${try(var.cloudwatch_log.name, null)}${local.suffix}"
  retention_in_days = try(var.cloudwatch_log.retention_in_days, null)
  log_group_class   = try(var.cloudwatch_log.log_group_class, null)
  skip_destroy      = try(var.cloudwatch_log.skip_destroy, null)

  lifecycle {
    precondition {
      condition     = try(var.cloudwatch_log.name, null) != null
      error_message = "When a SHARED_PER_ZONE log group is specified, the name is mandatory"
    }
  }
}
