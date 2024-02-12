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

  create_distribution = var.distribution.deployment == "CREATE"

  staging_alias    = var.aliases != null ? var.aliases.staging : one(module.open_next_aliases[*].alias_details.staging)
  production_alias = var.aliases != null ? var.aliases.production : one(module.open_next_aliases[*].alias_details.production)
  aliases          = var.aliases != null ? distinct(values(var.aliases)) : one(module.open_next_aliases[*].alias_details.aliases)

  prefix = var.prefix == null ? "" : "${var.prefix}-"
  suffix = var.suffix == null ? "" : "-${var.suffix}"

  zone = {
    server_domain_name             = lookup(module.server_function.url_hostnames, local.staging_alias, null)
    server_function_arn            = local.server_at_edge ? module.server_function.qualified_arn : module.server_function.arn
    server_at_edge                 = local.server_at_edge
    image_optimisation_domain_name = var.image_optimisation_function.create ? one(module.image_optimisation_function[*].url_hostnames)[local.staging_alias] : null
    use_auth_lambda                = var.server_function.backend_deployment_type == "REGIONAL_LAMBDA_WITH_AUTH_LAMBDA"
    bucket_domain_name             = local.website_bucket_domain_name
    bucket_origin_path             = "/${module.s3_assets.origin_asset_path}"
    reinvalidation_hash            = sha1(join("-", concat(module.s3_assets.file_hashes, [try(module.server_function.version, "")])))
  }

  user_supplied_behaviours = coalesce(var.behaviours, { custom_error_responses = null, static_assets = null, server = null, image_optimisation = null })
  behaviours = merge(local.user_supplied_behaviours, {
    static_assets = merge(coalesce(local.user_supplied_behaviours.static_assets, { paths = null, additional_paths = null, path_overrides = null, allowed_methods = null, cached_methods = null, cache_policy_id = null, origin_request_policy_id = null, compress = null, viewer_protocol_policy = null, viewer_request = null, viewer_response = null, origin_request = null, origin_response = null }), {
      additional_paths = try(coalesce(try(local.user_supplied_behaviours.static_assets.additional_paths, null), module.s3_assets.cloudfront_asset_mappings), [])
    })
  })

  server_at_edge = var.server_function.backend_deployment_type == "EDGE_LAMBDA"
  server_function_env_variables = merge(
    {
      "CACHE_BUCKET_NAME" : local.website_bucket_name,
      "CACHE_BUCKET_REGION" : local.website_bucket_region,
      "CACHE_BUCKET_KEY_PREFIX" : module.s3_assets.cache_key_prefix,
      "REVALIDATION_QUEUE_URL" : aws_sqs_queue.revalidation_queue.url,
      "REVALIDATION_QUEUE_REGION" : data.aws_region.current.name,
    },
    local.isr_tag_mapping_db_name != null ? { "CACHE_DYNAMO_TABLE" : local.isr_tag_mapping_db_name } : {},
    var.server_function.additional_environment_variables
  )

  custom_error_responses = [for custom_error_response in var.custom_error_responses : {
    bucket_domain_name    = local.zone.bucket_domain_name
    error_code            = custom_error_response.error_code
    error_caching_min_ttl = custom_error_response.error_caching_min_ttl
    response_code         = custom_error_response.response_code
    response_page = custom_error_response.response_page != null ? {
      name        = "${custom_error_response.error_code}.html"
      behaviour   = custom_error_response.response_page.path_prefix
      folder_path = "${local.staging_alias}/custom"
    } : null
  }]
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
  cache_policy              = var.distribution.cache_policy

  behaviours            = local.behaviours
  waf                   = var.waf
  domain_config         = var.domain_config
  continuous_deployment = var.continuous_deployment

  custom_error_responses = local.custom_error_responses

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

# Server Function

# As lambda@edge does not support environment variables, the module will injected them at the top of the server code prior to the code being uploaded to AWS, credit to SST for the inspiration behind this. https://github.com/sst/sst/blob/3b792053d90c49d9ca693308646a3389babe9ceb/packages/sst/src/constructs/EdgeFunction.ts#L193
resource "local_file" "lambda_at_edge_modifications" {
  count = local.server_at_edge && try(var.server_function.function_code.zip, null) == null && try(var.server_function.function_code.s3, null) == null ? 1 : 0

  content  = "process.env = { ...process.env, ...${jsonencode(local.server_function_env_variables)} };\r\n${file("${var.folder_path}/server-function/index.mjs")}"
  filename = "${var.folder_path}/server-function/index.mjs"
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
  iam_policy_statements = [
    {
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
    },
    {
      "Action" : [
        "sqs:SendMessage"
      ],
      "Resource" : aws_sqs_queue.revalidation_queue.arn,
      "Effect" : "Allow"
    },
    {
      "Action" : [
        "dynamodb:GetItem",
        "dynamodb:Query"
      ],
      "Resource" : [
        local.isr_tag_mapping_db_arn,
        "${local.isr_tag_mapping_db_arn}/index/*"
      ],
      "Effect" : "Allow"
    }
  ]

  environment_variables = local.server_at_edge ? {} : local.server_function_env_variables

  architecture   = try(coalesce(var.server_function.function_architecture, var.function_architecture), null)
  cloudwatch_log = try(coalesce(var.server_function.cloudwatch_log, var.cloudwatch_log), null)
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
    create             = local.server_at_edge == false
    authorization_type = var.server_function.backend_deployment_type == "REGIONAL_LAMBDA_WITH_AUTH_LAMBDA" ? "AWS_IAM" : "NONE"
    enable_streaming   = var.server_function.enable_streaming
  }

  scripts = var.scripts

  providers = {
    aws     = aws.server_function
    aws.iam = aws.iam
  }
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

  environment_variables = merge({
    "FUNCTION_NAME" : "${module.server_function.name}:${each.value}",
    "CONCURRENCY" : each.value == local.production_alias ? var.warmer_function.concurrency : coalesce(try(var.warmer_function.warm_staging.concurrency, null), var.warmer_function.concurrency)
  }, var.warmer_function.additional_environment_variables)

  additional_iam_policies = var.warmer_function.additional_iam_policies
  iam_policy_statements = [
    {
      "Action" : [
        "lambda:InvokeFunction"
      ],
      "Resource" : "${module.server_function.arn}:${each.value}",
      "Effect" : "Allow"
    }
  ]

  architecture   = try(coalesce(var.warmer_function.function_architecture, var.function_architecture), null)
  cloudwatch_log = try(coalesce(var.warmer_function.cloudwatch_log, var.cloudwatch_log, null))
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
  }, var.image_optimisation_function.additional_environment_variables)

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
  cloudwatch_log = try(coalesce(var.image_optimisation_function.cloudwatch_log, var.cloudwatch_log), null)
  iam            = try(coalesce(var.image_optimisation_function.iam, var.iam), null)
  vpc            = try(coalesce(var.image_optimisation_function.vpc, var.vpc), null)

  prefix = var.prefix
  suffix = var.suffix

  function_url = {
    create             = true
    authorization_type = var.image_optimisation_function.backend_deployment_type == "REGIONAL_LAMBDA_WITH_AUTH_LAMBDA" ? "AWS_IAM" : "NONE"
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
  cloudwatch_log = try(coalesce(var.revalidation_function.cloudwatch_log, var.cloudwatch_log), null)
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
