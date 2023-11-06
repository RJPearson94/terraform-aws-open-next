locals {
  root = "root"
  zones_map = merge({
    for zone in var.open_next.additional_zones : zone.name => {
      name        = zone.name,
      http_path   = trimsuffix(zone.http_path, "/"),
      folder_path = zone.folder_path
    }
    }, {
    root = {
      name        = local.root,
      http_path   = "",
      folder_path = var.open_next.root_folder_path
    }
  })
  zones                = keys(local.zones_map)
  zones_set            = toset(local.zones)
  additional_zones_set = toset([for zone in local.zones : zone if zone != local.root])

  assets_folders = {
    for name, zone in local.zones_map : name => "${zone.folder_path}/assets"
  }
  assets = flatten([
    for name, zone in local.zones_map :
    [for file in toset([for file in fileset(local.assets_folders[name], "**") : file if var.open_next.exclusion_regex != null ? length(regexall(var.open_next.exclusion_regex, file)) == 0 : true]) : {
      prefix = name == local.root ? "" : "${local.zones_map[name].http_path}/"
      zone   = zone
      file   = file
      hash   = filesha1("${local.assets_folders[name]}/${file}")
  }]])

  cache_folders = {
    for name, zone in local.zones_map : name => "${zone.folder_path}/cache"
  }
  cache_assets = flatten([
    for name, zone in local.zones_map :
    [for file in toset([for file in fileset(local.cache_folders[name], "**") : file if var.open_next.exclusion_regex != null ? length(regexall(var.open_next.exclusion_regex, file)) == 0 : true]) : {
      prefix = name == local.root ? "" : "${local.zones_map[name].http_path}/"
      zone   = zone
      file   = file
      hash   = filesha1("${local.cache_folders[name]}/${file}")
  }]])

  prefix = var.prefix == null ? "" : "${var.prefix}-"
  suffix = var.suffix == null ? "" : "-${var.suffix}"

  s3_origin_id          = "${local.prefix}s3-origin${local.suffix}"
  image_function_origin = "${local.prefix}image-function-origin${local.suffix}"
  server_function_origins = {
    for name, zone in local.zones_map : name => "${local.prefix}${name == local.root ? "" : "${name}-"}server-function-origin${local.suffix}"
  }
  origin_groups = {
    for name, zone in local.zones_map : name => "${local.prefix}${name == local.root ? "" : "${name}-"}origin-group${local.suffix}"
  }

  aliases = var.domain.create == true ? coalescelist(var.domain.alternate_names, [var.domain.name]) : tolist([])

  api_gateway_name    = "${local.prefix}website-backend-api-gateway${local.suffix}"
  api_gateway_version = "1.0.0"

  backend_type_api_gateway     = "API_GATEWAY"
  backend_type_regional_lambda = "REGIONAL_LAMBDA"
  backend_type_edge_lambda     = "EDGE_LAMBDA"

  image_optimisation_use_api_gateway  = var.image_optimisation_function.deployment == local.backend_type_api_gateway
  server_backend_use_api_gateway      = var.server_function.deployment == local.backend_type_api_gateway
  server_backend_use_edge_lambda      = var.server_function.deployment == local.backend_type_edge_lambda
  should_create_api_gateway_resources = local.image_optimisation_use_api_gateway || local.server_backend_use_api_gateway

  should_create_warmer_function                    = var.warmer_function.create == true && local.server_backend_use_edge_lambda == false
  should_create_revalidation_resources             = var.isr.create == true
  should_create_revalidation_tag_mapping_resources = var.isr.create == true && var.isr.tag_mapping_db.create == true

  tag_mapping_items = local.should_create_revalidation_tag_mapping_resources ? flatten([
    for name, zone in local.zones_map :
    fileexists("${zone.folder_path}/dynamodb-provider/dynamodb-cache.json") ? [for tag_mapping in jsondecode(file("${zone.folder_path}/dynamodb-provider/dynamodb-cache.json")) : {
      zone = zone
      item = tag_mapping
  }] : []]) : []
}

# S3

resource "aws_s3_bucket" "website_bucket" {
  bucket        = "${local.prefix}website-bucket${local.suffix}"
  force_destroy = var.force_destroy
}

resource "aws_s3_bucket_policy" "website_bucket_policy" {
  bucket = aws_s3_bucket.website_bucket.id
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
        "Resource" : "${aws_s3_bucket.website_bucket.arn}/*",
        "Effect" : "Allow",
        "Condition" : {
          "StringEquals" : {
            "AWS:SourceArn" : aws_cloudfront_distribution.website_distribution.arn
          }
        }
      }
    ]
  })
}

resource "aws_s3_object" "website_asset" {
  for_each = {
    for asset in local.assets : "${asset.zone.name}-${asset.file}" => asset
  }

  bucket = aws_s3_bucket.website_bucket.bucket
  key    = "${each.value.prefix}${each.value.file}"
  source = "${local.assets_folders[each.value.zone.name]}/${each.value.file}"
  etag   = filemd5("${local.assets_folders[each.value.zone.name]}/${each.value.file}")

  cache_control = length(regexall(var.cache_control_immutable_assets_regex, each.value.file)) > 0 ? "public,max-age=31536000,immutable" : "public,max-age=0,s-maxage=31536000,must-revalidate"
  content_type  = lookup(var.content_types.mapping, reverse(split(".", each.value.file))[0], var.content_types.default)
}

resource "aws_s3_object" "cache_asset" {
  for_each = {
    for asset in local.cache_assets : "${asset.zone.name}-${asset.file}" => asset
  }

  bucket = aws_s3_bucket.website_bucket.bucket
  key    = "${each.value.prefix}/_cache/${each.value.file}"
  source = "${local.cache_folders[each.value.zone.name]}/${each.value.file}"
  etag   = filemd5("${local.cache_folders[each.value.zone.name]}/${each.value.file}")

  content_type = lookup(var.content_types.mapping, reverse(split(".", each.value.file))[0], var.content_types.default)
}

# Server Function

module "server_function" {
  for_each = local.zones_set
  source   = "./modules/tf-aws-lambda"

  function_name = "${each.value == local.root ? "" : "${each.value}-"}server-function"
  zip_file      = data.archive_file.server_function[each.value].output_path
  hash          = data.archive_file.server_function[each.value].output_base64sha256

  runtime = var.server_function.runtime
  handler = "index.handler"

  memory_size = var.server_function.memory_size
  timeout     = var.server_function.timeout

  additional_iam_policies = var.server_function.additional_iam_policies
  iam_policy_statements = concat([
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
        aws_s3_bucket.website_bucket.arn,
        "${aws_s3_bucket.website_bucket.arn}/*"
      ],
      "Effect" : "Allow"
    },
    ],
    local.should_create_revalidation_resources ? [{
      "Action" : [
        "sqs:SendMessage"
      ],
      "Resource" : aws_sqs_queue.revalidation_queue[each.value].arn,
      "Effect" : "Allow"
    }] : [],
    local.should_create_revalidation_tag_mapping_resources ? [{
      "Action" : [
        "dynamodb:BatchGetItem",
        "dynamodb:GetRecords",
        "dynamodb:GetShardIterator",
        "dynamodb:Query",
        "dynamodb:GetItem",
        "dynamodb:Scan",
        "dynamodb:BatchWriteItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem",
        "dynamodb:DescribeTable"
      ],
      "Resource" : [
        aws_dynamodb_table.dynamodb_table[each.value].arn,
        "${aws_dynamodb_table.dynamodb_table[each.value].arn}/index/*"
      ],
      "Effect" : "Allow"
    }] : []
  )

  environment_variables = merge(
    local.should_create_revalidation_resources ? {
      "CACHE_BUCKET_NAME" : aws_s3_bucket.website_bucket.id,
      "CACHE_BUCKET_KEY_PREFIX" : "${each.value == local.root ? "" : "${each.value}/"}_cache",
      "CACHE_BUCKET_REGION" : data.aws_region.current.name,
      "REVALIDATION_QUEUE_URL" : aws_sqs_queue.revalidation_queue[each.value].url,
      "REVALIDATION_QUEUE_REGION" : data.aws_region.current.name,
    } : {},
    local.should_create_revalidation_tag_mapping_resources ? {
      "CACHE_DYNAMO_TABLE" : aws_dynamodb_table.dynamodb_table[each.value].name,
    } : {},
    var.server_function.additional_environment_variables
  )

  architecture = local.server_backend_use_edge_lambda ? "x86_64" : var.preferred_architecture

  iam            = var.iam
  cloudwatch_log = var.cloudwatch_log

  vpc = var.server_function.vpc != null ? var.server_function.vpc : var.vpc

  prefix = local.prefix
  suffix = local.suffix

  run_at_edge = local.server_backend_use_edge_lambda

  function_url = {
    create = var.server_function.deployment == local.backend_type_regional_lambda
  }

  providers = {
    aws     = aws.server_function
    aws.iam = aws.iam
  }
}

# Image Optimisation Function

module "image_optimisation_function" {
  source = "./modules/tf-aws-lambda"

  function_name = "image-optimization-function"
  zip_file      = data.archive_file.image_optimization_function.output_path
  hash          = data.archive_file.image_optimization_function.output_base64sha256

  runtime = var.image_optimisation_function.runtime
  handler = "index.handler"

  memory_size = var.image_optimisation_function.memory_size
  timeout     = var.image_optimisation_function.timeout

  environment_variables = merge({
    "BUCKET_NAME" = aws_s3_bucket.website_bucket.id
  }, var.image_optimisation_function.additional_environment_variables)

  additional_iam_policies = var.image_optimisation_function.additional_iam_policies
  iam_policy_statements = [
    {
      "Action" : [
        "s3:GetObject"
      ],
      "Resource" : "${aws_s3_bucket.website_bucket.arn}/*",
      "Effect" : "Allow"
    }
  ]

  architecture = var.preferred_architecture

  iam            = var.iam
  cloudwatch_log = var.cloudwatch_log

  vpc = var.image_optimisation_function.vpc != null ? var.image_optimisation_function.vpc : var.vpc

  prefix = local.prefix
  suffix = local.suffix

  function_url = {
    create = var.image_optimisation_function.deployment == local.backend_type_regional_lambda
  }

  providers = {
    aws.iam = aws.iam
  }
}

# Warmer Function

module "warmer_function" {
  for_each = local.should_create_warmer_function ? local.zones_set : []
  source   = "./modules/tf-aws-scheduled-lambda"

  function_name = "${each.value == local.root ? "" : "${each.value}-"}warmer-function"
  zip_file      = data.archive_file.warmer_function[each.value].output_path
  hash          = data.archive_file.warmer_function[each.value].output_base64sha256

  runtime = var.warmer_function.runtime
  handler = "index.handler"

  memory_size = var.warmer_function.memory_size
  timeout     = var.warmer_function.timeout

  environment_variables = merge({
    "FUNCTION_NAME" : module.server_function[each.value].function_name,
    "CONCURRENCY" : var.warmer_function.concurrency,
  }, var.warmer_function.additional_environment_variables)

  additional_iam_policies = var.warmer_function.additional_iam_policies
  iam_policy_statements = [
    {
      "Action" : [
        "lambda:InvokeFunction"
      ],
      "Resource" : module.server_function[each.value].function_arn,
      "Effect" : "Allow"
    }
  ]

  architecture = var.preferred_architecture

  iam            = var.iam
  cloudwatch_log = var.cloudwatch_log

  vpc = var.warmer_function.vpc != null ? var.warmer_function.vpc : var.vpc

  prefix = local.prefix
  suffix = local.suffix

  schedule = var.warmer_function.schedule

  providers = {
    aws.iam = aws.iam
  }
}

# Revalidation Function

module "revalidation_function" {
  for_each = local.should_create_revalidation_resources ? local.zones_set : []
  source   = "./modules/tf-aws-lambda"

  function_name = "${each.value == local.root ? "" : "${each.value}-"}revalidation-function"
  zip_file      = data.archive_file.revalidation_function[each.value].output_path
  hash          = data.archive_file.revalidation_function[each.value].output_base64sha256

  runtime = var.isr.revalidation_function.runtime
  handler = "index.handler"

  memory_size = var.isr.revalidation_function.memory_size
  timeout     = var.isr.revalidation_function.timeout

  environment_variables = var.isr.revalidation_function.additional_environment_variables

  additional_iam_policies = var.isr.revalidation_function.additional_iam_policies
  iam_policy_statements = [
    {
      "Action" : [
        "sqs:ReceiveMessage",
        "sqs:ChangeMessageVisibility",
        "sqs:GetQueueUrl",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes"
      ],
      "Resource" : aws_sqs_queue.revalidation_queue[each.value].arn,
      "Effect" : "Allow"
    }
  ]

  architecture = var.preferred_architecture

  iam            = var.iam
  cloudwatch_log = var.cloudwatch_log

  vpc = var.isr.revalidation_function.vpc != null ? var.isr.revalidation_function.vpc : var.vpc

  prefix = local.prefix
  suffix = local.suffix

  providers = {
    aws.iam = aws.iam
  }
}

# SQS

resource "aws_sqs_queue" "revalidation_queue" {
  for_each                    = local.should_create_revalidation_resources ? local.zones_set : []
  name                        = "${local.prefix}${each.value == local.root ? "" : "${each.value}-"}isr-queue${local.suffix}.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
}

resource "aws_lambda_event_source_mapping" "revalidation_queue_source" {
  for_each         = local.should_create_revalidation_resources ? local.zones_set : []
  event_source_arn = aws_sqs_queue.revalidation_queue[each.value].arn
  function_name    = module.revalidation_function[each.value].function_arn
}

# DynamoDB

resource "aws_dynamodb_table" "dynamodb_table" {
  for_each = local.should_create_revalidation_tag_mapping_resources ? local.zones_set : []
  name     = "${local.prefix}${each.value == local.root ? "" : "${each.value}-"}isr-tag-mapping${local.suffix}"

  billing_mode   = var.isr.tag_mapping_db.billing_mode
  read_capacity  = var.isr.tag_mapping_db.read_capacity
  write_capacity = var.isr.tag_mapping_db.write_capacity

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
    read_capacity   = var.isr.tag_mapping_db.read_capacity
    write_capacity  = var.isr.tag_mapping_db.write_capacity
  }
}

resource "aws_dynamodb_table_item" "isr_table_item" {
  for_each = {
    for tag_mapping_item in local.tag_mapping_items : "${tag_mapping_item.zone.name}-${tag_mapping_item.item.tag.S}" => tag_mapping_item
  }

  table_name = aws_dynamodb_table.dynamodb_table[each.value.zone.name].name
  hash_key   = aws_dynamodb_table.dynamodb_table[each.value.zone.name].hash_key
  range_key  = aws_dynamodb_table.dynamodb_table[each.value.zone.name].range_key

  item = jsonencode(each.value.item)
}

# API Gateway

resource "aws_apigatewayv2_api" "api" {
  count = local.should_create_api_gateway_resources ? 1 : 0

  name    = local.api_gateway_name
  version = local.api_gateway_version

  protocol_type = "HTTP"

  body = jsonencode({
    "openapi" : "3.0.3",
    "info" : {
      "title" : "${local.api_gateway_name}",
      "version" : "${local.api_gateway_version}"
    },
    "paths" : merge(
      local.image_optimisation_use_api_gateway ? {
        "/images/{proxy+}" : {
          "x-amazon-apigateway-any-method" : {
            "parameters" : [
              {
                "name" : "proxy",
                "in" : "path",
                "required" : true,
                "type" : "string"
              }
            ],
            "responses" : {},
            "x-amazon-apigateway-integration" : {
              "type" : "AWS_PROXY",
              "httpMethod" : "POST",
              "uri" : "${module.image_optimisation_function.invoke_arn}",
              "requestParameters" : {
                "overwrite:path" : "$request.path.proxy"
              },
              "payloadFormatVersion" : "2.0",
              "enableSimpleResponses" : true
            }
          }
        }
      } : {},
      local.server_backend_use_api_gateway ? {
        for zone in local.additional_zones_set : "/${zone}" => {
          "x-amazon-apigateway-any-method" : {
            "responses" : {},
            "x-amazon-apigateway-integration" : {
              "type" : "AWS_PROXY",
              "httpMethod" : "POST",
              "uri" : "${module.server_function[zone].invoke_arn}",
              "requestParameters" : {
                "overwrite:path" : "$request.path"
              },
              "payloadFormatVersion" : "2.0",
              "enableSimpleResponses" : true
            }
          }
        }
      } : {},
      local.server_backend_use_api_gateway ? {
        for zone in local.additional_zones_set : "/${zone}/{proxy+}" => {
          "x-amazon-apigateway-any-method" : {
            "parameters" : [
              {
                "name" : "proxy",
                "in" : "path",
                "required" : true,
                "type" : "string"
              }
            ],
            "responses" : {},
            "x-amazon-apigateway-integration" : {
              "type" : "AWS_PROXY",
              "httpMethod" : "POST",
              "uri" : "${module.server_function[zone].invoke_arn}",
              "requestParameters" : {
                "overwrite:path" : "$request.path"
              },
              "payloadFormatVersion" : "2.0",
              "enableSimpleResponses" : true
            }
          }
        }
      } : {},
      local.server_backend_use_api_gateway ? {
        "/$default" : {
          "x-amazon-apigateway-any-method" : {
            "isDefaultRoute" : true,
            "responses" : {},
            "x-amazon-apigateway-integration" : {
              "type" : "AWS_PROXY",
              "httpMethod" : "POST",
              "uri" : "${module.server_function[local.root].invoke_arn}",
              "requestParameters" : {
                "overwrite:path" : "$request.path"
              },
              "payloadFormatVersion" : "2.0",
              "enableSimpleResponses" : true
            }
          }
        }
      } : {}
    )
  })

  fail_on_warnings = true
}

resource "aws_apigatewayv2_deployment" "deployment" {
  count = local.should_create_api_gateway_resources ? 1 : 0

  api_id = one(aws_apigatewayv2_api.api[*].id)

  triggers = {
    redeployment = sha512(one(aws_apigatewayv2_api.api[*].body))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_apigatewayv2_stage" "stable" {
  count = local.should_create_api_gateway_resources ? 1 : 0

  api_id = one(aws_apigatewayv2_api.api[*].id)
  name   = "stable"

  deployment_id = one(aws_apigatewayv2_deployment.deployment[*].id)
}

resource "aws_lambda_permission" "server_function_permission" {
  for_each      = local.server_backend_use_api_gateway ? local.zones_set : []
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = module.server_function[each.value].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${one(aws_apigatewayv2_stage.stable[*].execution_arn)}/*"
}

resource "aws_lambda_permission" "image_optimisation_function_permission" {
  count         = local.image_optimisation_use_api_gateway ? 1 : 0
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = module.image_optimisation_function.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${one(aws_apigatewayv2_stage.stable[*].execution_arn)}/*"
}

# CloudFront

resource "aws_cloudfront_function" "x_forwarded_host" {
  name    = "${local.prefix}x-forwarded-host-function${local.suffix}"
  runtime = "cloudfront-js-1.0"
  publish = true
  code    = "\nfunction handler(event) {\n  var request = event.request;\n  request.headers[\"x-forwarded-host\"] = request.headers.host;\n  \n  return request;\n}"
}

resource "aws_cloudfront_origin_access_control" "website_origin_access_control" {
  name                              = "${local.prefix}website${local.suffix}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_cache_policy" "cache_policy" {
  name = "${local.prefix}cache-policy${local.suffix}"

  default_ttl = 0
  max_ttl     = 31536000
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "all"
    }
    headers_config {
      header_behavior = "whitelist"
      headers {
        items = ["accept", "rsc", "next-router-prefetch", "next-router-state-tree"]
      }
    }
    query_strings_config {
      query_string_behavior = "all"
    }
  }
}

resource "aws_cloudfront_distribution" "website_distribution" {
  dynamic "origin_group" {
    for_each = local.server_backend_use_edge_lambda ? [] : local.zones_set

    content {
      origin_id = local.origin_groups[origin_group.value]

      failover_criteria {
        status_codes = [503]
      }

      member {
        origin_id = local.server_function_origins[origin_group.value]
      }

      member {
        origin_id = local.s3_origin_id
      }
    }
  }

  origin {
    domain_name              = aws_s3_bucket.website_bucket.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.website_origin_access_control.id
    origin_id                = local.s3_origin_id
  }

  dynamic "origin" {
    for_each = local.server_backend_use_edge_lambda ? [] : local.zones_set

    content {
      domain_name = local.server_backend_use_api_gateway ? trimprefix(one(aws_apigatewayv2_api.api[*].api_endpoint), "https://") : module.server_function[origin.value].function_url_hostname
      origin_id   = local.server_function_origins[origin.value]
      origin_path = local.server_backend_use_api_gateway ? "/${one(aws_apigatewayv2_stage.stable[*].name)}" : null

      custom_origin_config {
        http_port              = 80
        https_port             = 443
        origin_protocol_policy = "https-only"
        origin_ssl_protocols   = ["TLSv1.2"]
      }
    }
  }

  origin {
    domain_name = local.image_optimisation_use_api_gateway ? trimprefix(one(aws_apigatewayv2_api.api[*].api_endpoint), "https://") : module.image_optimisation_function.function_url_hostname
    origin_id   = local.image_function_origin
    origin_path = local.image_optimisation_use_api_gateway ? "/${one(aws_apigatewayv2_stage.stable[*].name)}/images" : null

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  enabled         = var.cloudfront.enabled
  is_ipv6_enabled = var.cloudfront.ipv6_enabled
  http_version    = var.cloudfront.http_version
  web_acl_id      = try(var.waf.web_acl_id, null)

  dynamic "ordered_cache_behavior" {
    for_each = local.zones_set

    content {
      path_pattern     = "${ordered_cache_behavior.value == local.root ? "" : "${local.zones_map[ordered_cache_behavior.value].http_path}/"}api/*"
      allowed_methods  = ["GET", "HEAD", "OPTIONS", "PUT", "PATCH", "POST", "DELETE"]
      cached_methods   = ["GET", "HEAD", "OPTIONS"]
      target_origin_id = local.server_backend_use_edge_lambda ? local.s3_origin_id : local.server_function_origins[ordered_cache_behavior.value]

      cache_policy_id          = aws_cloudfront_cache_policy.cache_policy.id
      origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host_header.id

      compress               = true
      viewer_protocol_policy = "redirect-to-https"

      function_association {
        event_type   = "viewer-request"
        function_arn = aws_cloudfront_function.x_forwarded_host.arn
      }

      dynamic "lambda_function_association" {
        for_each = local.server_backend_use_edge_lambda ? [true] : []

        content {
          event_type   = "origin-request"
          lambda_arn   = module.server_function[ordered_cache_behavior.value].qualified_arn
          include_body = true
        }
      }
    }
  }

  dynamic "ordered_cache_behavior" {
    for_each = local.zones_set

    content {
      path_pattern     = "${ordered_cache_behavior.value == local.root ? "" : "${local.zones_map[ordered_cache_behavior.value].http_path}/"}_next/data/*"
      allowed_methods  = ["GET", "HEAD", "OPTIONS", "PUT", "PATCH", "POST", "DELETE"]
      cached_methods   = ["GET", "HEAD", "OPTIONS"]
      target_origin_id = local.server_backend_use_edge_lambda ? local.s3_origin_id : local.server_function_origins[ordered_cache_behavior.value]

      cache_policy_id          = aws_cloudfront_cache_policy.cache_policy.id
      origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host_header.id

      compress               = true
      viewer_protocol_policy = "redirect-to-https"

      function_association {
        event_type   = "viewer-request"
        function_arn = aws_cloudfront_function.x_forwarded_host.arn
      }

      dynamic "lambda_function_association" {
        for_each = local.server_backend_use_edge_lambda ? [true] : []

        content {
          event_type   = "origin-request"
          lambda_arn   = module.server_function[ordered_cache_behavior.value].qualified_arn
          include_body = true
        }
      }
    }
  }

  dynamic "ordered_cache_behavior" {
    for_each = local.zones_set

    content {
      path_pattern     = "${ordered_cache_behavior.value == local.root ? "" : "${local.zones_map[ordered_cache_behavior.value].http_path}/"}_next/image*"
      allowed_methods  = ["GET", "HEAD", "OPTIONS", "PUT", "PATCH", "POST", "DELETE"]
      cached_methods   = ["GET", "HEAD", "OPTIONS"]
      target_origin_id = local.image_function_origin

      cache_policy_id = aws_cloudfront_cache_policy.cache_policy.id

      compress               = true
      viewer_protocol_policy = "redirect-to-https"
    }
  }

  dynamic "ordered_cache_behavior" {
    for_each = local.zones_set

    content {
      path_pattern     = "${ordered_cache_behavior.value == local.root ? "" : "${local.zones_map[ordered_cache_behavior.value].http_path}/"}_next/*"
      allowed_methods  = ["GET", "HEAD", "OPTIONS"]
      cached_methods   = ["GET", "HEAD", "OPTIONS"]
      target_origin_id = local.s3_origin_id

      cache_policy_id = data.aws_cloudfront_cache_policy.caching_optimized.id

      compress               = true
      viewer_protocol_policy = "redirect-to-https"
    }
  }

  dynamic "ordered_cache_behavior" {
    for_each = local.additional_zones_set

    content {
      path_pattern     = "${local.zones_map[ordered_cache_behavior.value].http_path}/*"
      allowed_methods  = ["GET", "HEAD"]
      cached_methods   = ["GET", "HEAD"]
      target_origin_id = local.server_backend_use_edge_lambda ? local.s3_origin_id : local.origin_groups[ordered_cache_behavior.value]

      cache_policy_id          = aws_cloudfront_cache_policy.cache_policy.id
      origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host_header.id

      compress               = true
      viewer_protocol_policy = "redirect-to-https"

      function_association {
        event_type   = "viewer-request"
        function_arn = aws_cloudfront_function.x_forwarded_host.arn
      }

      dynamic "lambda_function_association" {
        for_each = local.server_backend_use_edge_lambda ? [true] : []

        content {
          event_type   = "origin-request"
          lambda_arn   = module.server_function[ordered_cache_behavior.value].qualified_arn
          include_body = true
        }
      }
    }
  }

  dynamic "ordered_cache_behavior" {
    for_each = local.additional_zones_set

    content {
      path_pattern     = local.zones_map[ordered_cache_behavior.value].http_path
      allowed_methods  = ["GET", "HEAD"]
      cached_methods   = ["GET", "HEAD"]
      target_origin_id = local.server_backend_use_edge_lambda ? local.s3_origin_id : local.origin_groups[ordered_cache_behavior.value]

      cache_policy_id          = aws_cloudfront_cache_policy.cache_policy.id
      origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host_header.id

      compress               = true
      viewer_protocol_policy = "redirect-to-https"

      function_association {
        event_type   = "viewer-request"
        function_arn = aws_cloudfront_function.x_forwarded_host.arn
      }

      dynamic "lambda_function_association" {
        for_each = local.server_backend_use_edge_lambda ? [true] : []

        content {
          event_type   = "origin-request"
          lambda_arn   = module.server_function[ordered_cache_behavior.value].qualified_arn
          include_body = true
        }
      }
    }
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.server_backend_use_edge_lambda ? local.s3_origin_id : local.origin_groups[local.root]

    cache_policy_id          = aws_cloudfront_cache_policy.cache_policy.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host_header.id

    compress               = true
    viewer_protocol_policy = "redirect-to-https"

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.x_forwarded_host.arn
    }

    dynamic "lambda_function_association" {
      for_each = local.server_backend_use_edge_lambda ? [true] : []

      content {
        event_type   = "origin-request"
        lambda_arn   = module.server_function[local.root].qualified_arn
        include_body = true
      }
    }
  }

  price_class = var.cloudfront.price_class

  restrictions {
    geo_restriction {
      restriction_type = var.cloudfront.geo_restrictions.type
      locations        = var.cloudfront.geo_restrictions.locations
    }
  }

  dynamic "viewer_certificate" {
    for_each = var.domain.create == false ? [{
      cloudfront_default_certificate = true
      }] : [{
      acm_certificate_arn      = var.domain.acm_certificate_arn
      minimum_protocol_version = var.cloudfront.minimum_protocol_version
      ssl_support_method       = var.cloudfront.ssl_support_method
    }]
    content {
      cloudfront_default_certificate = lookup(viewer_certificate.value, "cloudfront_default_certificate", null)
      acm_certificate_arn            = lookup(viewer_certificate.value, "acm_certificate_arn", null)
      minimum_protocol_version       = lookup(viewer_certificate.value, "minimum_protocol_version", null)
      ssl_support_method             = lookup(viewer_certificate.value, "ssl_support_method", null)
    }
  }

  aliases = local.aliases

  depends_on = [aws_s3_object.website_asset, aws_s3_object.cache_asset]
}

# Invalidate Distribution

resource "terraform_data" "invalidate_distribution" {
  count = var.cloudfront.invalidate_on_change ? 1 : 0

  triggers_replace = [
    flatten([for zone in local.zones : module.server_function[zone].function_version]),
    sha1(join("", [for f in aws_s3_object.website_asset : f.etag]))
  ]

  provisioner "local-exec" {
    command = "/bin/bash ${path.module}/scripts/invalidate-cloudfront.sh"

    environment = {
      "CDN_ID" = aws_cloudfront_distribution.website_distribution.id
    }
  }
}

# Route 53

resource "aws_route53_record" "route53_a_record" {
  for_each = toset(local.aliases)

  zone_id = one(data.aws_route53_zone.hosted_zone[*].zone_id)
  name    = each.value
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.website_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.website_distribution.hosted_zone_id
    evaluate_target_health = var.domain.evaluate_target_health
  }

  provider = aws.dns
}

resource "aws_route53_record" "route53_aaaa_record" {
  for_each = var.cloudfront.ipv6_enabled == true ? toset(local.aliases) : toset([])

  zone_id = one(data.aws_route53_zone.hosted_zone[*].zone_id)
  name    = each.value
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.website_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.website_distribution.hosted_zone_id
    evaluate_target_health = var.domain.evaluate_target_health
  }

  provider = aws.dns
}
