locals {
  prefix = var.prefix == null ? "" : "${var.prefix}-"
  suffix = var.suffix == null ? "" : "-${var.suffix}"

  s3_origin_id                       = "s3-origin"
  image_optimisation_function_origin = "image-optimisation-function-origin"
  server_function_origin             = "server-function-origin"

  create_cache_policy = var.cache_policy.deployment == "CREATE"
  cache_policy_id     = local.create_cache_policy ? one(aws_cloudfront_cache_policy.cache_policy[*].id) : var.cache_policy.arn

  custom_error_responses = [for custom_error_response in var.custom_error_responses : merge(custom_error_response, { path_pattern = "/${custom_error_response.response_page.behaviour}/*" }) if custom_error_response.response_page != null]

  # Force the root zone to the bottom of the behaviours
  zones = concat([for zone in var.zones : zone if zone.root == false], [for zone in var.zones : zone if zone.root == true])

  ordered_cache_behaviors = concat(
    [
      for custom_error_response in local.custom_error_responses : {
        path_pattern     = custom_error_response.path_pattern
        allowed_methods  = coalesce(try(var.behaviours.custom_error_pages.path_overrides[custom_error_response.path_pattern].allowed_methods, null), try(var.behaviours.custom_error_pages.allowed_methods, null), ["GET", "HEAD", "OPTIONS"])
        cached_methods   = coalesce(try(var.behaviours.custom_error_pages.path_overrides[custom_error_response.path_pattern].cached_methods, null), try(var.behaviours.custom_error_pages.cached_methods, null), ["GET", "HEAD", "OPTIONS"])
        target_origin_id = join("-", compact([custom_error_response.error_code, local.s3_origin_id]))

        cache_policy_id          = coalesce(try(var.behaviours.custom_error_pages.path_overrides[custom_error_response.path_pattern].cache_policy_id, null), try(var.behaviours.custom_error_pages.cache_policy_id, null), data.aws_cloudfront_cache_policy.caching_optimized.id)
        origin_request_policy_id = try(coalesce(try(var.behaviours.custom_error_pages.path_overrides[custom_error_response.path_pattern].origin_request_policy_id, null), try(var.behaviours.custom_error_pages.origin_request_policy_id, null)), null)

        compress               = coalesce(try(var.behaviours.custom_error_pages.path_overrides[custom_error_response.path_pattern].compress, null), try(var.behaviours.custom_error_pages.compress, null), true)
        viewer_protocol_policy = coalesce(try(var.behaviours.custom_error_pages.path_overrides[custom_error_response.path_pattern].viewer_protocol_policy, null), try(var.behaviours.custom_error_pages.viewer_protocol_policy, null), "redirect-to-https")

        function_associations = [
          merge(coalesce(try(var.behaviours.custom_error_pages.path_overrides[custom_error_response.path_pattern].viewer_request, null), try(var.behaviours.custom_error_pages.viewer_request, null), { type = "CLOUDFRONT_FUNCTION", arn = null }), { event_type = "viewer-request" }),
          merge(coalesce(try(var.behaviours.custom_error_pages.path_overrides[custom_error_response.path_pattern].viewer_response, null), try(var.behaviours.custom_error_pages.viewer_response, null), { type = "CLOUDFRONT_FUNCTION", arn = null }), { event_type = "viewer-response" }),
        ]

        lambda_function_associations = [
          merge(coalesce(try(var.behaviours.custom_error_pages.path_overrides[custom_error_response.path_pattern].viewer_request, null), try(var.behaviours.custom_error_pages.viewer_request, null), { type = "LAMBDA@EDGE", arn = null }), { event_type = "viewer-request" }),
          merge(coalesce(try(var.behaviours.custom_error_pages.path_overrides[custom_error_response.path_pattern].viewer_response, null), try(var.behaviours.custom_error_pages.viewer_response, null), { type = "LAMBDA@EDGE", arn = null }), { event_type = "viewer-response" }),
          merge(coalesce(try(var.behaviours.custom_error_pages.path_overrides[custom_error_response.path_pattern].origin_request, null), try(var.behaviours.custom_error_pages.origin_request, null), { arn = null }), { type = "LAMBDA@EDGE", event_type = "origin-request" }),
          merge(coalesce(try(var.behaviours.custom_error_pages.path_overrides[custom_error_response.path_pattern].origin_response, null), try(var.behaviours.custom_error_pages.origin_response, null), { arn = null }), { type = "LAMBDA@EDGE", event_type = "origin-response" }),
        ]
      }
    ],
    flatten([
      for zone in local.zones : concat(
        [for index, static_assets_behaviour in formatlist("%s%s", zone.root == true ? zone.path != null ? "/${zone.path}" : "" : "/${coalesce(zone.path, zone.name)}", coalesce(try(var.behaviours.static_assets.zone_overrides[zone.name].paths, null), try(var.behaviours.static_assets.paths, null), concat(["/_next/static/*"], coalesce(try(var.behaviours.static_assets.zone_overrides[zone.name].additional_paths, null), try(var.behaviours.static_assets.additional_paths, null), [])))) : {
          path_pattern     = static_assets_behaviour
          allowed_methods  = coalesce(try(var.behaviours.static_assets.path_overrides[static_assets_behaviour].allowed_methods, null), try(var.behaviours.static_assets.allowed_methods, null), ["GET", "HEAD", "OPTIONS"])
          cached_methods   = coalesce(try(var.behaviours.static_assets.path_overrides[static_assets_behaviour].cached_methods, null), try(var.behaviours.static_assets.cached_methods, null), ["GET", "HEAD", "OPTIONS"])
          target_origin_id = join("-", compact([zone.name, local.s3_origin_id]))

          cache_policy_id          = coalesce(try(var.behaviours.static_assets.path_overrides[static_assets_behaviour].cache_policy_id, null), try(var.behaviours.static_assets.cache_policy_id, null), data.aws_cloudfront_cache_policy.caching_optimized.id)
          origin_request_policy_id = try(coalesce(try(var.behaviours.static_assets.path_overrides[static_assets_behaviour].origin_request_policy_id, null), try(var.behaviours.static_assets.origin_request_policy_id, null)), null)

          compress               = coalesce(try(var.behaviours.static_assets.path_overrides[static_assets_behaviour].compress, null), try(var.behaviours.static_assets.compress, null), true)
          viewer_protocol_policy = coalesce(try(var.behaviours.static_assets.path_overrides[static_assets_behaviour].viewer_protocol_policy, null), try(var.behaviours.static_assets.viewer_protocol_policy, null), "redirect-to-https")

          function_associations = [
            merge(coalesce(try(var.behaviours.static_assets.path_overrides[static_assets_behaviour].viewer_request, null), try(var.behaviours.static_assets.viewer_request, null), { type = "CLOUDFRONT_FUNCTION", arn = null }), { event_type = "viewer-request" }),
            merge(coalesce(try(var.behaviours.static_assets.path_overrides[static_assets_behaviour].viewer_response, null), try(var.behaviours.static_assets.viewer_response, null), { type = "CLOUDFRONT_FUNCTION", arn = null }), { event_type = "viewer-response" }),
          ]

          lambda_function_associations = [
            merge(coalesce(try(var.behaviours.static_assets.path_overrides[static_assets_behaviour].viewer_request, null), try(var.behaviours.static_assets.viewer_request, null), { type = "LAMBDA@EDGE", arn = null }), { event_type = "viewer-request" }),
            merge(coalesce(try(var.behaviours.static_assets.path_overrides[static_assets_behaviour].viewer_response, null), try(var.behaviours.static_assets.viewer_response, null), { type = "LAMBDA@EDGE", arn = null }), { event_type = "viewer-response" }),
            merge(coalesce(try(var.behaviours.static_assets.path_overrides[static_assets_behaviour].origin_request, null), try(var.behaviours.static_assets.origin_request, null), { arn = null }), { type = "LAMBDA@EDGE", event_type = "origin-request" }),
            merge(coalesce(try(var.behaviours.static_assets.path_overrides[static_assets_behaviour].origin_response, null), try(var.behaviours.static_assets.origin_response, null), { arn = null }), { type = "LAMBDA@EDGE", event_type = "origin-response" }),
          ]
          }
        ],
        [for index, image_optimisation_behaviour in zone.image_optimisation_domain_name == null ? [] : formatlist("%s%s", zone.root == true ? zone.path != null ? "/${zone.path}" : "" : "/${coalesce(zone.path, zone.name)}", coalesce(try(var.behaviours.image_optimisation.zone_overrides[zone.name].paths, null), try(var.behaviours.image_optimisation.paths, null), ["/_next/image"])) : {
          path_pattern     = image_optimisation_behaviour
          allowed_methods  = coalesce(try(var.behaviours.image_optimisation.path_overrides[image_optimisation_behaviour].allowed_methods, null), try(var.behaviours.image_optimisation.allowed_methods, null), ["GET", "HEAD", "OPTIONS", "PUT", "PATCH", "POST", "DELETE"])
          cached_methods   = coalesce(try(var.behaviours.image_optimisation.path_overrides[image_optimisation_behaviour].cached_methods, null), try(var.behaviours.image_optimisation.cached_methods, null), ["GET", "HEAD", "OPTIONS"])
          target_origin_id = join("-", compact([zone.name, local.image_optimisation_function_origin]))

          cache_policy_id          = coalesce(try(var.behaviours.image_optimisation.path_overrides[image_optimisation_behaviour].cache_policy_id, null), try(var.behaviours.image_optimisation.cache_policy_id, null), local.cache_policy_id)
          origin_request_policy_id = coalesce(try(var.behaviours.image_optimisation.path_overrides[image_optimisation_behaviour].origin_request_policy_id, null), try(var.behaviours.image_optimisation.origin_request_policy_id, null), data.aws_cloudfront_origin_request_policy.all_viewer_except_host_header.id)

          compress               = coalesce(try(var.behaviours.image_optimisation.path_overrides[image_optimisation_behaviour].compress, null), try(var.behaviours.image_optimisation.compress, null), true)
          viewer_protocol_policy = coalesce(try(var.behaviours.image_optimisation.path_overrides[image_optimisation_behaviour].viewer_protocol_policy, null), try(var.behaviours.image_optimisation.viewer_protocol_policy, null), "redirect-to-https")

          function_associations = [
            merge(coalesce(try(var.behaviours.image_optimisation.path_overrides[image_optimisation_behaviour].viewer_request, null), try(var.behaviours.image_optimisation.viewer_request, null), { type = "CLOUDFRONT_FUNCTION", arn = null }), { event_type = "viewer-request" }),
            merge(coalesce(try(var.behaviours.image_optimisation.path_overrides[image_optimisation_behaviour].viewer_response, null), try(var.behaviours.image_optimisation.viewer_response, null), { type = "CLOUDFRONT_FUNCTION", arn = null }), { event_type = "viewer-response" }),
          ]

          lambda_function_associations = [
            merge(coalesce(try(var.behaviours.image_optimisation.path_overrides[image_optimisation_behaviour].viewer_request, null), try(var.behaviours.image_optimisation.viewer_request, null), { type = "LAMBDA@EDGE", arn = null }), { event_type = "viewer-request" }),
            merge(coalesce(try(var.behaviours.image_optimisation.path_overrides[image_optimisation_behaviour].viewer_response, null), try(var.behaviours.image_optimisation.viewer_response, null), { type = "LAMBDA@EDGE", arn = null }), { event_type = "viewer-response" }),
            merge(coalesce(try(var.behaviours.image_optimisation.path_overrides[image_optimisation_behaviour].origin_request, null), try(var.behaviours.image_optimisation.origin_request, null), { arn = zone.use_auth_lambda ? one(module.auth_function[*].qualified_arn) : null, include_body = true }), { type = "LAMBDA@EDGE", event_type = "origin-request" }),
            merge(coalesce(try(var.behaviours.image_optimisation.path_overrides[image_optimisation_behaviour].origin_response, null), try(var.behaviours.image_optimisation.origin_response, null), { arn = null }), { type = "LAMBDA@EDGE", event_type = "origin-response" }),
          ]
        }],
        [for index, server_behaviour in formatlist("%s%s", zone.root == true ? zone.path != null ? "/${zone.path}" : "" : "/${coalesce(zone.path, zone.name)}", coalesce(try(var.behaviours.server.zone_overrides[zone.name].paths, null), try(var.behaviours.server.paths, null), ["/_next/data/*", "/api/*", "*"])) : {
          path_pattern     = server_behaviour
          allowed_methods  = coalesce(try(var.behaviours.server.path_overrides[server_behaviour].allowed_methods, null), try(var.behaviours.server.allowed_methods, null), ["GET", "HEAD", "OPTIONS", "PUT", "PATCH", "POST", "DELETE"])
          cached_methods   = coalesce(try(var.behaviours.server.path_overrides[server_behaviour].cached_methods, null), try(var.behaviours.server.cached_methods, null), ["GET", "HEAD", "OPTIONS"])
          target_origin_id = zone.server_at_edge ? join("-", compact([zone.name, local.s3_origin_id])) : join("-", compact([zone.name, local.server_function_origin]))

          cache_policy_id          = coalesce(try(var.behaviours.server.path_overrides[server_behaviour].cache_policy_id, null), try(var.behaviours.server.cache_policy_id, null), local.cache_policy_id)
          origin_request_policy_id = coalesce(try(var.behaviours.server.path_overrides[server_behaviour].origin_request_policy_id, null), try(var.behaviours.server.origin_request_policy_id, null), data.aws_cloudfront_origin_request_policy.all_viewer_except_host_header.id)

          compress               = coalesce(try(var.behaviours.server.path_overrides[server_behaviour].compress, null), try(var.behaviours.server.compress, null), true)
          viewer_protocol_policy = coalesce(try(var.behaviours.server.path_overrides[server_behaviour].viewer_protocol_policy, null), try(var.behaviours.server.viewer_protocol_policy, null), "redirect-to-https")

          function_associations = [
            merge(coalesce(try(var.behaviours.server.path_overrides[server_behaviour].viewer_request, null), try(var.behaviours.server.viewer_request, null), { type = "CLOUDFRONT_FUNCTION", arn = aws_cloudfront_function.x_forwarded_host.arn }), { event_type = "viewer-request" }),
            merge(coalesce(try(var.behaviours.server.path_overrides[server_behaviour].viewer_response, null), try(var.behaviours.server.viewer_response, null), { type = "CLOUDFRONT_FUNCTION", arn = null }), { event_type = "viewer-response" }),
          ]

          lambda_function_associations = [
            merge(coalesce(try(var.behaviours.server.path_overrides[server_behaviour].viewer_request, null), try(var.behaviours.server.viewer_request, null), { type = "LAMBDA@EDGE", arn = null }), { event_type = "viewer-request" }),
            merge(coalesce(try(var.behaviours.server.path_overrides[server_behaviour].viewer_response, null), try(var.behaviours.server.viewer_response, null), { type = "LAMBDA@EDGE", arn = null }), { event_type = "viewer-response" }),
            merge(coalesce(try(var.behaviours.server.path_overrides[server_behaviour].origin_request, null), try(var.behaviours.server.origin_request, null), { arn = zone.server_at_edge ? zone.server_function_arn : zone.use_auth_lambda ? one(module.auth_function[*].qualified_arn) : null, include_body = true }), { type = "LAMBDA@EDGE", event_type = "origin-request" }),
            merge(coalesce(try(var.behaviours.server.path_overrides[server_behaviour].origin_response, null), try(var.behaviours.server.origin_response, null), { arn = null }), { type = "LAMBDA@EDGE", event_type = "origin-response" }),
          ]
        }]
      )
    ])
  )

  origins = concat(
    [
      for custom_error_response in local.custom_error_responses : {
        domain_name              = custom_error_response.bucket_domain_name
        origin_access_control_id = aws_cloudfront_origin_access_control.website_origin_access_control.id
        origin_id                = join("-", compact([custom_error_response.error_code, local.s3_origin_id]))
        origin_path              = "/${custom_error_response.response_page.folder_path}"
        origin_headers           = null
        custom_origin_config     = null
      }
    ],
    flatten([
      for zone in local.zones : concat([{
        domain_name              = zone.bucket_domain_name
        origin_access_control_id = aws_cloudfront_origin_access_control.website_origin_access_control.id
        origin_id                = join("-", compact([zone.name, local.s3_origin_id]))
        origin_path              = zone.bucket_origin_path
        origin_headers           = null
        custom_origin_config     = null
        }],
        zone.server_at_edge ? [] : [{
          domain_name              = zone.server_domain_name
          origin_access_control_id = null
          origin_id                = join("-", compact([zone.name, local.server_function_origin]))
          origin_path              = null
          origin_headers           = zone.server_origin_headers
          custom_origin_config = {
            http_port              = 80
            https_port             = 443
            origin_protocol_policy = "https-only"
            origin_ssl_protocols   = ["TLSv1.2"]
          }
        }],
        zone.image_optimisation_domain_name == null ? [] : [{
          domain_name              = zone.image_optimisation_domain_name
          origin_access_control_id = null
          origin_id                = join("-", compact([zone.name, local.image_optimisation_function_origin]))
          origin_path              = null
          origin_headers           = null
          custom_origin_config = {
            http_port              = 80
            https_port             = 443
            origin_protocol_policy = "https-only"
            origin_ssl_protocols   = ["TLSv1.2"]
          }
      }])
    ])
  )

  web_acl_id           = contains(["DETACH", "NONE"], var.waf.deployment) ? null : var.waf.deployment == "USE_EXISTING" ? var.waf.web_acl_id : one(aws_wafv2_web_acl.distribution_waf[*].arn)
  waf_rate_limit_rules = try(var.waf.rate_limiting.enabled, false) == true ? var.waf.rate_limiting.limits : []
  rules = concat(
    [
      for rule in local.waf_rate_limit_rules : {
        name                         = join("-", compact(["aws-rate-based-rule", rule.rule_name_suffix, rule.limit]))
        priority                     = rule.priority
        managed_rule_group_statement = null
        action                       = rule.behaviour
        block_action                 = null
        logical_rule                 = null
        rate_based_statement = {
          limit              = rule.limit
          aggregate_key_type = "IP"
          geo_match_scope    = rule.geo_match_scope
        }
        ip_set_reference_statements = null
        byte_match_statement        = null
      }
    ],
    [
      for aws_managed_rule in var.waf.aws_managed_rules : {
        name     = aws_managed_rule.name
        priority = aws_managed_rule.priority
        managed_rule_group_statement = {
          name                       = aws_managed_rule.aws_managed_rule_name
          managed_rule_group_configs = null
        }
        action                      = null
        block_action                = null
        logical_rule                = null
        rate_based_statement        = null
        ip_set_reference_statements = null
        byte_match_statement        = null
      }
    ],
    try(var.waf.sqli.enabled, false) ? [{
      name     = "sqli"
      priority = var.waf.sqli.priority
      managed_rule_group_statement = {
        name                       = "AWSManagedRulesSQLiRuleSet"
        managed_rule_group_configs = null
      }
      action                      = null
      block_action                = null
      logical_rule                = null
      rate_based_statement        = null
      ip_set_reference_statements = null
      byte_match_statement        = null
    }] : [],
    try(var.waf.account_takeover_protection.enabled, false) ? [{
      name     = "account-takeover-protection"
      priority = var.waf.account_takeover_protection.priority
      managed_rule_group_statement = {
        name = "AWSManagedRulesATPRuleSet"
        managed_rule_group_configs = {
          aws_managed_rules_atp_rule_set  = var.waf.account_takeover_protection
          aws_managed_rules_acfp_rule_set = null
        }
      }
      action                      = null
      block_action                = null
      logical_rule                = null
      rate_based_statement        = null
      ip_set_reference_statements = null
      byte_match_statement        = null
    }] : [],
    try(var.waf.account_creation_fraud_prevention.enabled, false) ? [{
      name     = "account-creation-fraud-prevention"
      priority = var.waf.account_creation_fraud_prevention.priority
      managed_rule_group_statement = {
        name = "AWSManagedRulesACFPRuleSet"
        managed_rule_group_configs = {
          aws_managed_rules_atp_rule_set  = null
          aws_managed_rules_acfp_rule_set = var.waf.account_creation_fraud_prevention
        }
      }
      action                      = null
      block_action                = null
      logical_rule                = null
      rate_based_statement        = null
      ip_set_reference_statements = null
      byte_match_statement        = null
    }] : [],
    try(var.waf.enforce_basic_auth.enabled, false) ? [{
      name     = "basic-auth"
      priority = var.waf.enforce_basic_auth.priority
      action   = "BLOCK"
      block_action = {
        response_code            = var.waf.enforce_basic_auth.response_code
        response_header          = var.waf.enforce_basic_auth.response_header
        custom_response_body_key = null
      }
      logical_rule                 = var.waf.enforce_basic_auth.ip_address_restrictions != null ? "AND" : null
      managed_rule_group_statement = null
      rate_based_statement         = null
      ip_set_reference_statements = var.waf.enforce_basic_auth.ip_address_restrictions != null ? [for ip_address_restriction in var.waf.enforce_basic_auth.ip_address_restrictions : {
        not = ip_address_restriction.action == "BYPASS"
        arn = coalesce(ip_address_restriction.arn, aws_wafv2_ip_set.ip_set[ip_address_restriction.name].arn)
      }] : null
      byte_match_statement = {
        not                   = true
        positional_constraint = "EXACTLY"
        // I would make this configurable to allow it to be marked as sensitive or not however Terraform panics when you use the sensitive function as part of a ternary
        // This has been marked as sensitive by default if you need to see all rules, see this discussion https://discuss.hashicorp.com/t/how-to-show-sensitive-values/24076/4
        search_string = "Basic ${sensitive(base64encode("${var.waf.enforce_basic_auth.credentials.username}:${var.waf.enforce_basic_auth.credentials.password}"))}"
        field_to_match = {
          single_header = {
            name = var.waf.enforce_basic_auth.header_name
          }
        }
        text_transformation = {
          priority = 0
          type     = "NONE"
        }
      }
    }] : [],
    var.waf.additional_rules != null ? [for additional_rule in var.waf.additional_rules : {
      name         = additional_rule.name
      priority     = additional_rule.priority
      action       = additional_rule.action
      block_action = additional_rule.block_action
      logical_rule = null
      ip_set_reference_statements = try(length(additional_rule.ip_address_restrictions), 0) > 0 ? [for ip_address_restriction in additional_rule.ip_address_restrictions : {
        not = ip_address_restriction.action == "BYPASS"
        arn = coalesce(ip_address_restriction.arn, aws_wafv2_ip_set.ip_set[ip_address_restriction.name].arn)
      }] : []
      managed_rule_group_statement = null
      rate_based_statement         = null
      byte_match_statement         = null
    } if additional_rule.enabled] : []
  )

  should_create_auth_lambda = contains(["DETACH", "CREATE"], var.auth_function.deployment) || length({ for zone in local.zones : "distribution" => zone if try(zone.use_auth_lambda, false) == true }) > 0

  aliases = var.domain_config != null ? formatlist(join(".", compact([var.domain_config.sub_domain, "%s"])), distinct([for hosted_zone in var.domain_config.hosted_zones : hosted_zone.name])) : []
  route53_entries = try(var.domain_config.create_route53_entries, false) == true ? { for hosted_zone in var.domain_config.hosted_zones : join("-", compact([hosted_zone.name, hosted_zone.id, hosted_zone.private_zone])) => {
    name    = join(".", compact([var.domain_config.sub_domain, hosted_zone.name]))
    zone_id = coalesce(hosted_zone.id, data.aws_route53_zone.hosted_zone[join("-", compact([hosted_zone.name, hosted_zone.private_zone]))].zone_id)
  } } : {}
}

# Functions

module "auth_function" {
  count  = local.should_create_auth_lambda ? 1 : 0
  source = "../tf-aws-lambda"

  prefix        = var.prefix
  suffix        = var.suffix
  function_name = "auth-function"

  function_code = {
    zip = try(var.auth_function.function_code.s3, null) == null ? coalesce(try(var.auth_function.function_code.zip, null), {
      path = one(data.archive_file.auth_function[*].output_path)
      hash = one(data.archive_file.auth_function[*].output_base64sha256)
    }) : null
    s3 = try(var.auth_function.function_code.s3, null)
  }

  handler     = try(var.auth_function.function_code.handler, "index.handler")
  run_at_edge = true

  runtime     = var.auth_function.runtime
  memory_size = var.auth_function.memory_size
  timeout     = var.auth_function.timeout

  additional_iam_policies = var.auth_function.additional_iam_policies
  iam_policy_statements = [
    {
      "Action" : [
        "lambda:InvokeFunctionUrl"
      ],
      "Resource" : flatten([for zone in local.zones : [zone.server_function_arn, "${zone.server_function_arn}:*"] if zone.use_auth_lambda == true && zone.server_function_arn != null]),
      "Effect" : "Allow"
    }
  ]

  environment_variables = {}
  architecture          = "x86_64"

  aliases = {
    create = false
  }

  function_url = {
    create = false
  }

  providers = {
    aws.iam = aws.iam
  }
}

resource "aws_cloudfront_function" "x_forwarded_host" {
  name    = "${local.prefix}x-forwarded-host-function${local.suffix}"
  runtime = coalesce(try(var.x_forwarded_host_function.runtime, null), "cloudfront-js-1.0")
  publish = true
  code    = coalesce(try(var.x_forwarded_host_function.code, null), file("${path.module}/code/xForwardedHost.js"))
}

# CloudFront

resource "aws_cloudfront_origin_access_control" "website_origin_access_control" {
  name                              = "${local.prefix}website${local.suffix}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_cache_policy" "cache_policy" {
  count = local.create_cache_policy ? 1 : 0
  name  = "${local.prefix}cache-policy${local.suffix}"

  default_ttl = var.cache_policy.default_ttl
  max_ttl     = var.cache_policy.max_ttl
  min_ttl     = var.cache_policy.min_ttl

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = var.cache_policy.cookie_behavior
    }

    headers_config {
      header_behavior = var.cache_policy.header_behavior

      headers {
        items = var.cache_policy.header_items
      }
    }

    query_strings_config {
      query_string_behavior = var.cache_policy.query_string_behavior
    }
  }
}

resource "aws_cloudfront_distribution" "website_distribution" {
  count = var.continuous_deployment.use ? 0 : 1

  dynamic "origin" {
    for_each = local.origins

    content {
      domain_name              = origin.value.domain_name
      origin_access_control_id = origin.value.origin_access_control_id
      origin_id                = origin.value.origin_id
      origin_path              = origin.value.origin_path

      dynamic "custom_header" {
        for_each = coalesce(origin.value.origin_headers, {})

        content {
          name  = custom_header.key
          value = custom_header.value
        }
      }

      dynamic "custom_origin_config" {
        for_each = origin.value.custom_origin_config != null ? [true] : []

        content {
          http_port              = origin.value.custom_origin_config.http_port
          https_port             = origin.value.custom_origin_config.https_port
          origin_protocol_policy = origin.value.custom_origin_config.origin_protocol_policy
          origin_ssl_protocols   = origin.value.custom_origin_config.origin_ssl_protocols
        }
      }
    }
  }

  enabled         = var.enabled
  is_ipv6_enabled = var.ipv6_enabled
  http_version    = var.http_version
  web_acl_id      = local.web_acl_id

  dynamic "ordered_cache_behavior" {
    for_each = [for ordered_cache_behavior in local.ordered_cache_behaviors : ordered_cache_behavior if ordered_cache_behavior.path_pattern != "*"]

    content {
      path_pattern     = ordered_cache_behavior.value.path_pattern
      allowed_methods  = ordered_cache_behavior.value.allowed_methods
      cached_methods   = ordered_cache_behavior.value.cached_methods
      target_origin_id = ordered_cache_behavior.value.target_origin_id

      cache_policy_id          = ordered_cache_behavior.value.cache_policy_id
      origin_request_policy_id = ordered_cache_behavior.value.origin_request_policy_id

      compress               = ordered_cache_behavior.value.compress
      viewer_protocol_policy = ordered_cache_behavior.value.viewer_protocol_policy

      dynamic "function_association" {
        for_each = { for function_association in ordered_cache_behavior.value.function_associations : function_association.event_type => function_association if function_association.type == "CLOUDFRONT_FUNCTION" && function_association.arn != null }

        content {
          event_type   = function_association.value.event_type
          function_arn = function_association.value.arn
        }
      }

      dynamic "lambda_function_association" {
        for_each = { for lambda_function_association in ordered_cache_behavior.value.lambda_function_associations : lambda_function_association.event_type => lambda_function_association if lambda_function_association.type == "LAMBDA@EDGE" && lambda_function_association.arn != null }

        content {
          event_type   = lambda_function_association.value.event_type
          lambda_arn   = lambda_function_association.value.arn
          include_body = lambda_function_association.value.include_body
        }
      }
    }
  }

  dynamic "default_cache_behavior" {
    for_each = [for default_cache_behavior in local.ordered_cache_behaviors : default_cache_behavior if default_cache_behavior.path_pattern == "*"]

    content {
      allowed_methods  = default_cache_behavior.value.allowed_methods
      cached_methods   = default_cache_behavior.value.cached_methods
      target_origin_id = default_cache_behavior.value.target_origin_id

      cache_policy_id          = default_cache_behavior.value.cache_policy_id
      origin_request_policy_id = default_cache_behavior.value.origin_request_policy_id

      compress               = default_cache_behavior.value.compress
      viewer_protocol_policy = default_cache_behavior.value.viewer_protocol_policy

      dynamic "function_association" {
        for_each = { for function_association in default_cache_behavior.value.function_associations : function_association.event_type => function_association if function_association.type == "CLOUDFRONT_FUNCTION" && function_association.arn != null }

        content {
          event_type   = function_association.value.event_type
          function_arn = function_association.value.arn
        }
      }

      dynamic "lambda_function_association" {
        for_each = { for lambda_function_association in default_cache_behavior.value.lambda_function_associations : lambda_function_association.event_type => lambda_function_association if lambda_function_association.type == "LAMBDA@EDGE" && lambda_function_association.arn != null }

        content {
          event_type   = lambda_function_association.value.event_type
          lambda_arn   = lambda_function_association.value.arn
          include_body = lambda_function_association.value.include_body
        }
      }
    }
  }

  price_class = var.price_class

  restrictions {
    geo_restriction {
      restriction_type = var.geo_restrictions.type
      locations        = var.geo_restrictions.locations
    }
  }

  dynamic "viewer_certificate" {
    for_each = try(var.domain_config.viewer_certificate.acm_certificate_arn, null) == null ? [{ cloudfront_default_certificate = true }] : [var.domain_config.viewer_certificate]
    content {
      cloudfront_default_certificate = try(viewer_certificate.value.cloudfront_default_certificate, null)
      acm_certificate_arn            = try(viewer_certificate.value.acm_certificate_arn, null)
      minimum_protocol_version       = try(viewer_certificate.value.minimum_protocol_version, null)
      ssl_support_method             = try(viewer_certificate.value.ssl_support_method, null)
    }
  }

  dynamic "custom_error_response" {
    for_each = var.custom_error_responses
    content {
      error_code            = custom_error_response.value.error_code
      error_caching_min_ttl = try(custom_error_response.value.error_caching_min_ttl, null)
      response_code         = try(custom_error_response.value.response_code, null)
      response_page_path    = try(custom_error_response.value.response_page, null) != null ? "/${custom_error_response.value.response_page.behaviour}/${custom_error_response.value.response_page.name}" : null
    }
  }

  aliases = local.aliases
}

# We have 2 different resources as Terraform doesn't currently support having dynamic lifecycle rules
resource "aws_cloudfront_distribution" "production_distribution" {
  count = var.continuous_deployment.use ? 1 : 0
  dynamic "origin" {
    for_each = local.origins

    content {
      domain_name              = origin.value.domain_name
      origin_access_control_id = origin.value.origin_access_control_id
      origin_id                = origin.value.origin_id
      origin_path              = origin.value.origin_path

      dynamic "custom_header" {
        for_each = coalesce(origin.value.origin_headers, {})

        content {
          name  = custom_header.key
          value = custom_header.value
        }
      }

      dynamic "custom_origin_config" {
        for_each = origin.value.custom_origin_config != null ? [true] : []

        content {
          http_port              = origin.value.custom_origin_config.http_port
          https_port             = origin.value.custom_origin_config.https_port
          origin_protocol_policy = origin.value.custom_origin_config.origin_protocol_policy
          origin_ssl_protocols   = origin.value.custom_origin_config.origin_ssl_protocols
        }
      }
    }
  }

  continuous_deployment_policy_id = contains(["ACTIVE", "PROMOTE"], var.continuous_deployment.deployment) ? one(aws_cloudfront_continuous_deployment_policy.continuous_deployment_policy[*].id) : null

  enabled         = var.enabled
  is_ipv6_enabled = var.ipv6_enabled
  http_version    = var.http_version
  web_acl_id      = local.web_acl_id

  dynamic "ordered_cache_behavior" {
    for_each = [for ordered_cache_behavior in local.ordered_cache_behaviors : ordered_cache_behavior if ordered_cache_behavior.path_pattern != "*"]

    content {
      path_pattern     = ordered_cache_behavior.value.path_pattern
      allowed_methods  = ordered_cache_behavior.value.allowed_methods
      cached_methods   = ordered_cache_behavior.value.cached_methods
      target_origin_id = ordered_cache_behavior.value.target_origin_id

      cache_policy_id          = ordered_cache_behavior.value.cache_policy_id
      origin_request_policy_id = ordered_cache_behavior.value.origin_request_policy_id

      compress               = ordered_cache_behavior.value.compress
      viewer_protocol_policy = ordered_cache_behavior.value.viewer_protocol_policy

      dynamic "function_association" {
        for_each = { for function_association in ordered_cache_behavior.value.function_associations : function_association.event_type => function_association if function_association.type == "CLOUDFRONT_FUNCTION" && function_association.arn != null }

        content {
          event_type   = function_association.value.event_type
          function_arn = function_association.value.arn
        }
      }

      dynamic "lambda_function_association" {
        for_each = { for lambda_function_association in ordered_cache_behavior.value.lambda_function_associations : lambda_function_association.event_type => lambda_function_association if lambda_function_association.type == "LAMBDA@EDGE" && lambda_function_association.arn != null }

        content {
          event_type   = lambda_function_association.value.event_type
          lambda_arn   = lambda_function_association.value.arn
          include_body = lambda_function_association.value.include_body
        }
      }
    }
  }

  dynamic "default_cache_behavior" {
    for_each = [for default_cache_behavior in local.ordered_cache_behaviors : default_cache_behavior if default_cache_behavior.path_pattern == "*"]

    content {
      allowed_methods  = default_cache_behavior.value.allowed_methods
      cached_methods   = default_cache_behavior.value.cached_methods
      target_origin_id = default_cache_behavior.value.target_origin_id

      cache_policy_id          = default_cache_behavior.value.cache_policy_id
      origin_request_policy_id = default_cache_behavior.value.origin_request_policy_id

      compress               = default_cache_behavior.value.compress
      viewer_protocol_policy = default_cache_behavior.value.viewer_protocol_policy

      dynamic "function_association" {
        for_each = { for function_association in default_cache_behavior.value.function_associations : function_association.event_type => function_association if function_association.type == "CLOUDFRONT_FUNCTION" && function_association.arn != null }

        content {
          event_type   = function_association.value.event_type
          function_arn = function_association.value.arn
        }
      }

      dynamic "lambda_function_association" {
        for_each = { for lambda_function_association in default_cache_behavior.value.lambda_function_associations : lambda_function_association.event_type => lambda_function_association if lambda_function_association.type == "LAMBDA@EDGE" && lambda_function_association.arn != null }

        content {
          event_type   = lambda_function_association.value.event_type
          lambda_arn   = lambda_function_association.value.arn
          include_body = lambda_function_association.value.include_body
        }
      }
    }
  }

  price_class = var.price_class

  restrictions {
    geo_restriction {
      restriction_type = var.geo_restrictions.type
      locations        = var.geo_restrictions.locations
    }
  }

  dynamic "viewer_certificate" {
    for_each = try(var.domain_config.viewer_certificate.acm_certificate_arn, null) == null ? [{ cloudfront_default_certificate = true }] : [var.domain_config.viewer_certificate]
    content {
      cloudfront_default_certificate = try(viewer_certificate.value.cloudfront_default_certificate, null)
      acm_certificate_arn            = try(viewer_certificate.value.acm_certificate_arn, null)
      minimum_protocol_version       = try(viewer_certificate.value.minimum_protocol_version, null)
      ssl_support_method             = try(viewer_certificate.value.ssl_support_method, null)
    }
  }

  dynamic "custom_error_response" {
    for_each = var.custom_error_responses
    content {
      error_code            = custom_error_response.value.error_code
      error_caching_min_ttl = try(custom_error_response.value.error_caching_min_ttl, null)
      response_code         = try(custom_error_response.value.response_code, null)
      response_page_path    = try(custom_error_response.value.response_page, null) != null ? "/${custom_error_response.value.response_page.folder_path}/${custom_error_response.value.response_page.name}" : null
    }
  }

  aliases = local.aliases

  lifecycle {
    ignore_changes = [origin, ordered_cache_behavior, default_cache_behavior]
  }
}

resource "aws_cloudfront_distribution" "staging_distribution" {
  count = var.continuous_deployment.use && var.continuous_deployment.deployment != "NONE" ? 1 : 0

  dynamic "origin" {
    for_each = local.origins

    content {
      domain_name              = origin.value.domain_name
      origin_access_control_id = origin.value.origin_access_control_id
      origin_id                = origin.value.origin_id
      origin_path              = origin.value.origin_path

      dynamic "custom_header" {
        for_each = coalesce(origin.value.origin_headers, {})

        content {
          name  = custom_header.key
          value = custom_header.value
        }
      }

      dynamic "custom_origin_config" {
        for_each = origin.value.custom_origin_config != null ? [true] : []

        content {
          http_port              = origin.value.custom_origin_config.http_port
          https_port             = origin.value.custom_origin_config.https_port
          origin_protocol_policy = origin.value.custom_origin_config.origin_protocol_policy
          origin_ssl_protocols   = origin.value.custom_origin_config.origin_ssl_protocols
        }
      }
    }
  }

  staging         = true
  enabled         = var.enabled
  is_ipv6_enabled = var.ipv6_enabled
  http_version    = var.http_version
  web_acl_id      = local.web_acl_id

  dynamic "ordered_cache_behavior" {
    for_each = [for ordered_cache_behavior in local.ordered_cache_behaviors : ordered_cache_behavior if ordered_cache_behavior.path_pattern != "*"]

    content {
      path_pattern     = ordered_cache_behavior.value.path_pattern
      allowed_methods  = ordered_cache_behavior.value.allowed_methods
      cached_methods   = ordered_cache_behavior.value.cached_methods
      target_origin_id = ordered_cache_behavior.value.target_origin_id

      cache_policy_id          = ordered_cache_behavior.value.cache_policy_id
      origin_request_policy_id = ordered_cache_behavior.value.origin_request_policy_id

      compress               = ordered_cache_behavior.value.compress
      viewer_protocol_policy = ordered_cache_behavior.value.viewer_protocol_policy

      dynamic "function_association" {
        for_each = { for function_association in ordered_cache_behavior.value.function_associations : function_association.event_type => function_association if function_association.type == "CLOUDFRONT_FUNCTION" && function_association.arn != null }

        content {
          event_type   = function_association.value.event_type
          function_arn = function_association.value.arn
        }
      }

      dynamic "lambda_function_association" {
        for_each = { for lambda_function_association in ordered_cache_behavior.value.lambda_function_associations : lambda_function_association.event_type => lambda_function_association if lambda_function_association.type == "LAMBDA@EDGE" && lambda_function_association.arn != null }

        content {
          event_type   = lambda_function_association.value.event_type
          lambda_arn   = lambda_function_association.value.arn
          include_body = lambda_function_association.value.include_body
        }
      }
    }
  }

  dynamic "default_cache_behavior" {
    for_each = [for default_cache_behavior in local.ordered_cache_behaviors : default_cache_behavior if default_cache_behavior.path_pattern == "*"]

    content {
      allowed_methods  = default_cache_behavior.value.allowed_methods
      cached_methods   = default_cache_behavior.value.cached_methods
      target_origin_id = default_cache_behavior.value.target_origin_id

      cache_policy_id          = default_cache_behavior.value.cache_policy_id
      origin_request_policy_id = default_cache_behavior.value.origin_request_policy_id

      compress               = default_cache_behavior.value.compress
      viewer_protocol_policy = default_cache_behavior.value.viewer_protocol_policy

      dynamic "function_association" {
        for_each = { for function_association in default_cache_behavior.value.function_associations : function_association.event_type => function_association if function_association.type == "CLOUDFRONT_FUNCTION" && function_association.arn != null }

        content {
          event_type   = function_association.value.event_type
          function_arn = function_association.value.arn
        }
      }

      dynamic "lambda_function_association" {
        for_each = { for lambda_function_association in default_cache_behavior.value.lambda_function_associations : lambda_function_association.event_type => lambda_function_association if lambda_function_association.type == "LAMBDA@EDGE" && lambda_function_association.arn != null }

        content {
          event_type   = lambda_function_association.value.event_type
          lambda_arn   = lambda_function_association.value.arn
          include_body = lambda_function_association.value.include_body
        }
      }
    }
  }

  price_class = var.price_class

  restrictions {
    geo_restriction {
      restriction_type = var.geo_restrictions.type
      locations        = var.geo_restrictions.locations
    }
  }

  dynamic "viewer_certificate" {
    for_each = try(var.domain_config.viewer_certificate.acm_certificate_arn, null) == null ? [{
      cloudfront_default_certificate = true
      }] : [{
      acm_certificate_arn      = var.domain_config.viewer_certificate.acm_certificate_arn
      minimum_protocol_version = var.domain_config.viewer_certificate.minimum_protocol_version
      ssl_support_method       = var.domain_config.viewer_certificate.ssl_support_method
    }]
    content {
      cloudfront_default_certificate = try(viewer_certificate.value.cloudfront_default_certificate, null)
      acm_certificate_arn            = try(viewer_certificate.value.acm_certificate_arn, null)
      minimum_protocol_version       = try(viewer_certificate.value.minimum_protocol_version, null)
      ssl_support_method             = try(viewer_certificate.value.ssl_support_method, null)
    }
  }

  dynamic "custom_error_response" {
    for_each = var.custom_error_responses
    content {
      error_code            = custom_error_response.value.error_code
      error_caching_min_ttl = try(custom_error_response.value.error_caching_min_ttl, null)
      response_code         = try(custom_error_response.value.response_code, null)
      response_page_path    = try(custom_error_response.value.response_page, null) != null ? "/${custom_error_response.value.response_page.folder_path}/${custom_error_response.value.response_page.name}" : null
    }
  }

  aliases = local.aliases
}

resource "aws_cloudfront_continuous_deployment_policy" "continuous_deployment_policy" {
  count   = var.continuous_deployment.use && var.continuous_deployment.deployment != "NONE" ? 1 : 0
  enabled = var.continuous_deployment.deployment != "DETACH"

  staging_distribution_dns_names {
    items    = [one(aws_cloudfront_distribution.staging_distribution[*].domain_name)]
    quantity = 1
  }

  traffic_config {
    type = try(var.continuous_deployment.traffic_config.header, null) != null ? "SingleHeader" : "SingleWeight"

    dynamic "single_header_config" {
      for_each = var.continuous_deployment.traffic_config.header != null ? [var.continuous_deployment.traffic_config.header] : []
      content {
        header = single_header_config.value.name
        value  = single_header_config.value.value
      }
    }

    dynamic "single_weight_config" {
      for_each = try(var.continuous_deployment.traffic_config.weight, null) != null ? [var.continuous_deployment.traffic_config.weight] : []
      content {
        weight = single_weight_config.value.percentage

        dynamic "session_stickiness_config" {
          for_each = try(single_weight_config.value.session_stickiness, null) != null ? [single_weight_config.value.session_stickiness] : []
          content {
            idle_ttl    = session_stickiness_config.value.idle_ttl
            maximum_ttl = session_stickiness_config.value.maximum_ttl
          }
        }
      }
    }
  }
}

resource "terraform_data" "invalidate_production_distribution" {
  count = var.continuous_deployment.use == false || var.continuous_deployment.deployment == "PROMOTE" ? 1 : 0

  triggers_replace = [
    sha1(join("-", [for zone in var.zones : zone.reinvalidation_hash])),
    sha1(join("-", [for origin in local.origins : sha1(jsonencode(origin))])),
    sha1(join("-", [for ordered_cache_behavior in local.ordered_cache_behaviors : sha1(jsonencode(ordered_cache_behavior))]))
  ]

  provisioner "local-exec" {
    command = "/bin/bash ${path.module}/scripts/invalidate-cloudfront.sh"

    environment = {
      "CDN_ID" = var.continuous_deployment.use ? one(aws_cloudfront_distribution.production_distribution[*].id) : one(aws_cloudfront_distribution.website_distribution[*].id)
    }
  }

  depends_on = [terraform_data.promote_distribution]
}

resource "terraform_data" "invalidate_staging_distribution" {
  count = var.continuous_deployment.use && var.continuous_deployment.deployment == "ACTIVE" ? 1 : 0

  triggers_replace = [
    sha1(join("-", [for zone in var.zones : zone.reinvalidation_hash])),
    sha1(join("-", [for origin in local.origins : sha1(jsonencode(origin))])),
    sha1(join("-", [for origin in local.ordered_cache_behaviors : sha1(jsonencode(origin))]))
  ]

  provisioner "local-exec" {
    command = "/bin/bash ${path.module}/scripts/invalidate-cloudfront.sh"

    environment = {
      "CDN_ID" = one(aws_cloudfront_distribution.staging_distribution[*].id)
    }
  }
}

resource "terraform_data" "promote_distribution" {
  count = var.continuous_deployment.use && var.continuous_deployment.deployment == "PROMOTE" ? 1 : 0

  provisioner "local-exec" {
    command = "/bin/bash ${path.module}/scripts/promote-distribution.sh"

    environment = {
      "SCRIPT_FOLDER_PATH"  = "${path.module}/scripts"
      "CDN_PRODUCTION_ID"   = one(aws_cloudfront_distribution.production_distribution[*].id)
      "CDN_PRODUCTION_ETAG" = one(aws_cloudfront_distribution.production_distribution[*].etag)
      "CDN_STAGING_ID"      = one(aws_cloudfront_distribution.staging_distribution[*].id)
      "CDN_STAGING_ETAG"    = one(aws_cloudfront_distribution.staging_distribution[*].etag)
    }
  }
}

# This is a workaround for a bug in the v5 of the AWS terraform provider. More info can be found at https://github.com/hashicorp/terraform-provider-aws/issues/34511
resource "terraform_data" "remove_continuous_deployment_id" {
  count = var.continuous_deployment.use && var.continuous_deployment.deployment == "DETACH" ? 1 : 0

  provisioner "local-exec" {
    command = "/bin/bash ${path.module}/scripts/remove-continuous-deployment-policy-id.sh"

    environment = {
      "CDN_PRODUCTION_ID" = one(aws_cloudfront_distribution.production_distribution[*].id)
    }
  }
}

# WAF

resource "aws_wafv2_web_acl" "distribution_waf" {
  count = contains(["DETACH", "CREATE"], var.waf.deployment) ? 1 : 0
  name  = "${local.prefix}website-waf${local.suffix}"
  scope = "CLOUDFRONT"

  dynamic "default_action" {
    for_each = var.waf.default_action != null ? [var.waf.default_action] : [{ action = "ALLOW", block_action = null }]
    content {
      dynamic "allow" {
        for_each = default_action.value.action == "ALLOW" ? [true] : []
        content {}
      }

      dynamic "block" {
        for_each = default_action.value.action == "BLOCK" ? [true] : []
        content {
          dynamic "custom_response" {
            for_each = default_action.value.block_action != null ? [default_action.value.block_action] : []
            content {
              response_code            = custom_response.value.response_code
              custom_response_body_key = custom_response.value.custom_response_body_key

              dynamic "response_header" {
                for_each = custom_response.value.response_header != null ? [custom_response.value.response_header] : []
                content {
                  name  = response_header.value.name
                  value = response_header.value.value
                }
              }
            }
          }
        }
      }
    }
  }

  dynamic "custom_response_body" {
    for_each = var.waf.custom_response_bodies != null ? var.waf.custom_response_bodies : []
    content {
      key          = custom_response_body.value.key
      content      = custom_response_body.value.content
      content_type = custom_response_body.value.content_type
    }
  }

  dynamic "rule" {
    for_each = local.rules

    content {
      name     = "${local.prefix}${rule.value.name}${local.suffix}"
      priority = coalesce(rule.value.priority, index(local.rules, rule.value))

      dynamic "action" {
        for_each = rule.value.action != null ? [rule.value.action] : []
        content {
          dynamic "count" {
            for_each = action.value == "COUNT" ? [true] : []
            content {}
          }

          dynamic "block" {
            for_each = action.value == "BLOCK" ? [true] : []
            content {
              dynamic "custom_response" {
                for_each = rule.value.block_action != null ? [rule.value.block_action] : []
                content {
                  response_code            = custom_response.value.response_code
                  custom_response_body_key = custom_response.value.custom_response_body_key

                  dynamic "response_header" {
                    for_each = custom_response.value.response_header != null ? [custom_response.value.response_header] : []
                    content {
                      name  = response_header.value.name
                      value = response_header.value.value
                    }
                  }
                }
              }
            }
          }
        }
      }

      dynamic "override_action" {
        for_each = rule.value.logical_rule == null && rule.value.managed_rule_group_statement != null ? [true] : []
        content {
          none {}
        }
      }

      statement {
        dynamic "managed_rule_group_statement" {
          for_each = rule.value.logical_rule == null && rule.value.managed_rule_group_statement != null ? [rule.value.managed_rule_group_statement] : []
          content {
            name        = managed_rule_group_statement.value.name
            vendor_name = "AWS"

            dynamic "managed_rule_group_configs" {
              for_each = managed_rule_group_statement.value.managed_rule_group_configs != null ? [managed_rule_group_statement.value.managed_rule_group_configs] : []
              content {
                dynamic "aws_managed_rules_acfp_rule_set" {
                  for_each = managed_rule_group_configs.value.aws_managed_rules_acfp_rule_set != null ? [managed_rule_group_configs.value.aws_managed_rules_acfp_rule_set] : []
                  content {
                    creation_path          = aws_managed_rules_acfp_rule_set.value.creation_path
                    registration_page_path = aws_managed_rules_acfp_rule_set.value.registration_page_path
                    enable_regex_in_path   = aws_managed_rules_acfp_rule_set.value.enable_regex_in_path

                    dynamic "request_inspection" {
                      for_each = aws_managed_rules_acfp_rule_set.value.request_inspection != null ? [aws_managed_rules_acfp_rule_set.value.request_inspection] : []
                      content {
                        email_field {
                          identifier = request_inspection.value.email_field_identifier
                        }
                        username_field {
                          identifier = request_inspection.value.username_field_identifier
                        }
                        password_field {
                          identifier = request_inspection.value.password_field_identifier
                        }
                        payload_type = request_inspection.value.payload_type
                      }
                    }

                    dynamic "response_inspection" {
                      for_each = aws_managed_rules_acfp_rule_set.value.response_inspection != null ? [aws_managed_rules_acfp_rule_set.value.response_inspection] : []
                      content {
                        status_code {
                          failure_codes = response_inspection.value.failure_codes
                          success_codes = response_inspection.value.success_codes
                        }
                      }
                    }
                  }
                }

                dynamic "aws_managed_rules_atp_rule_set" {
                  for_each = managed_rule_group_configs.value.aws_managed_rules_atp_rule_set != null ? [managed_rule_group_configs.value.aws_managed_rules_atp_rule_set] : []
                  content {
                    login_path           = aws_managed_rules_atp_rule_set.value.login_path
                    enable_regex_in_path = aws_managed_rules_atp_rule_set.value.enable_regex_in_path

                    dynamic "request_inspection" {
                      for_each = aws_managed_rules_atp_rule_set.value.request_inspection != null ? [aws_managed_rules_atp_rule_set.value.request_inspection] : []
                      content {
                        username_field {
                          identifier = request_inspection.value.username_field_identifier
                        }
                        password_field {
                          identifier = request_inspection.value.password_field_identifier
                        }
                        payload_type = request_inspection.value.payload_type
                      }
                    }

                    dynamic "response_inspection" {
                      for_each = aws_managed_rules_atp_rule_set.value.response_inspection != null ? [aws_managed_rules_atp_rule_set.value.response_inspection] : []
                      content {
                        status_code {
                          failure_codes = response_inspection.value.failure_codes
                          success_codes = response_inspection.value.success_codes
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }

        dynamic "rate_based_statement" {
          for_each = rule.value.logical_rule == null && rule.value.rate_based_statement != null ? [rule.value.rate_based_statement] : []
          content {
            limit              = rate_based_statement.value.limit
            aggregate_key_type = rate_based_statement.value.aggregate_key_type

            dynamic "scope_down_statement" {
              for_each = try(length(rate_based_statement.value.geo_match_scope), 0) > 0 ? [true] : []
              content {
                geo_match_statement {
                  country_codes = rate_based_statement.value.geo_match_scope
                }
              }
            }
          }
        }

        dynamic "ip_set_reference_statement" {
          for_each = rule.value.logical_rule == null && try(length(rule.value.ip_set_reference_statements), 0) == 1 && try(rule.value.ip_set_reference_statements[0].not, null) == false ? rule.value.ip_set_reference_statements : []
          content {
            arn = ip_set_reference_statement.value.arn
          }
        }

        dynamic "byte_match_statement" {
          for_each = rule.value.logical_rule == null && try(rule.value.byte_match_statement.not, null) == false ? [rule.value.byte_match_statement] : []
          content {
            positional_constraint = byte_match_statement.value.positional_constraint
            search_string         = byte_match_statement.value.search_string
            field_to_match {
              single_header {
                name = byte_match_statement.value.field_to_match.single_header.name
              }
            }
            text_transformation {
              priority = byte_match_statement.value.text_transformation.priority
              type     = byte_match_statement.value.text_transformation.type
            }
          }
        }

        dynamic "not_statement" {
          for_each = rule.value.logical_rule == null && ((try(length(rule.value.ip_set_reference_statements), 0) == 1 && try(rule.value.ip_set_reference_statements[0].not, null) == true) || try(rule.value.byte_match_statement.not, false)) ? [true] : []
          content {
            statement {
              dynamic "ip_set_reference_statement" {
                for_each = try(length(rule.value.ip_set_reference_statements), 0) == 1 ? rule.value.ip_set_reference_statements : []
                content {
                  arn = ip_set_reference_statement.value.arn
                }
              }

              dynamic "byte_match_statement" {
                for_each = rule.value.byte_match_statement != null ? [rule.value.byte_match_statement] : []
                content {
                  positional_constraint = byte_match_statement.value.positional_constraint
                  search_string         = byte_match_statement.value.search_string
                  field_to_match {
                    single_header {
                      name = byte_match_statement.value.field_to_match.single_header.name
                    }
                  }
                  text_transformation {
                    priority = byte_match_statement.value.text_transformation.priority
                    type     = byte_match_statement.value.text_transformation.type
                  }
                }
              }
            }
          }
        }

        dynamic "and_statement" {
          for_each = rule.value.logical_rule == "AND" ? [true] : []
          content {
            dynamic "statement" {
              for_each = rule.value.logical_rule == null && try(length(rule.value.ip_set_reference_statements), 0) == 1 && try(rule.value.ip_set_reference_statements[0].not, null) == false ? rule.value.ip_set_reference_statements : []
              content {
                ip_set_reference_statement {
                  arn = statement.value.arn
                }
              }
            }

            dynamic "statement" {
              for_each = try(rule.value.byte_match_statement.not, null) == false ? [rule.value.byte_match_statement] : []
              content {
                byte_match_statement {
                  positional_constraint = statement.value.positional_constraint
                  search_string         = statement.value.search_string
                  field_to_match {
                    single_header {
                      name = statement.value.field_to_match.single_header.name
                    }
                  }
                  text_transformation {
                    priority = statement.value.text_transformation.priority
                    type     = statement.value.text_transformation.type
                  }
                }
              }
            }

            dynamic "statement" {
              for_each = try(length(rule.value.ip_set_reference_statements), 0) > 2 ? [true] : []
              content {
                or_statement {
                  dynamic "statement" {
                    for_each = [for ip_set_reference_statement in rule.value.ip_set_reference_statements : ip_set_reference_statement if ip_set_reference_statement.not == false]
                    content {
                      ip_set_reference_statement {
                        arn = statement.value.arn
                      }
                    }
                  }
                }

                dynamic "statement" {
                  for_each = [for ip_set_reference_statement in rule.value.ip_set_reference_statements : ip_set_reference_statement if ip_set_reference_statement.not == true]
                  content {
                    not_statement {
                      statement {
                        ip_set_reference_statement {
                          arn = statement.value.arn
                        }
                      }
                    }
                  }
                }
              }
            }

            dynamic "statement" {
              for_each = try(rule.value.byte_match_statement.not, null) == true ? [rule.value.byte_match_statement] : []
              content {
                not_statement {
                  statement {
                    byte_match_statement {
                      positional_constraint = statement.value.positional_constraint
                      search_string         = statement.value.search_string
                      field_to_match {
                        single_header {
                          name = statement.value.field_to_match.single_header.name
                        }
                      }
                      text_transformation {
                        priority = statement.value.text_transformation.priority
                        type     = statement.value.text_transformation.type
                      }
                    }
                  }
                }
              }
            }
          }
        }

        dynamic "or_statement" {
          for_each = try(length(rule.value.ip_set_reference_statements), 0) > 1 ? [true] : []
          content {
            dynamic "statement" {
              for_each = [for ip_set_reference_statement in rule.value.ip_set_reference_statements : ip_set_reference_statement if ip_set_reference_statement.not == false]
              content {
                ip_set_reference_statement {
                  arn = statement.value.arn
                }
              }
            }

            dynamic "statement" {
              for_each = [for ip_set_reference_statement in rule.value.ip_set_reference_statements : ip_set_reference_statement if ip_set_reference_statement.not == true]
              content {
                not_statement {
                  statement {
                    ip_set_reference_statement {
                      arn = statement.value.arn
                    }
                  }
                }
              }
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${local.prefix}${rule.value.name}${local.suffix}"
        sampled_requests_enabled   = true
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.prefix}website-waf-metric${local.suffix}"
    sampled_requests_enabled   = true
  }

  depends_on = [aws_wafv2_ip_set.ip_set]
}

resource "aws_wafv2_ip_set" "ip_set" {
  for_each = contains(["DETACH", "CREATE"], var.waf.deployment) ? coalesce(var.waf.ip_addresses, {}) : {}

  name               = "${local.prefix}${each.key}${local.suffix}"
  description        = each.value.description
  scope              = "CLOUDFRONT"
  ip_address_version = each.value.ip_address_version
  addresses          = each.value.addresses
}

# Route 53

resource "aws_route53_record" "route53_a_record" {
  for_each = local.route53_entries

  zone_id = each.value.zone_id
  name    = each.value.name
  type    = "A"

  alias {
    name                   = var.continuous_deployment.use ? one(aws_cloudfront_distribution.production_distribution[*].domain_name) : one(aws_cloudfront_distribution.website_distribution[*].domain_name)
    zone_id                = var.continuous_deployment.use ? one(aws_cloudfront_distribution.production_distribution[*].hosted_zone_id) : one(aws_cloudfront_distribution.website_distribution[*].hosted_zone_id)
    evaluate_target_health = var.domain_config.evaluate_target_health
  }

  provider = aws.dns
}

resource "aws_route53_record" "route53_aaaa_record" {
  for_each = var.ipv6_enabled == true ? local.route53_entries : {}

  zone_id = each.value.zone_id
  name    = each.value.name
  type    = "AAAA"

  alias {
    name                   = var.continuous_deployment.use ? one(aws_cloudfront_distribution.production_distribution[*].domain_name) : one(aws_cloudfront_distribution.website_distribution[*].domain_name)
    zone_id                = var.continuous_deployment.use ? one(aws_cloudfront_distribution.production_distribution[*].hosted_zone_id) : one(aws_cloudfront_distribution.website_distribution[*].hosted_zone_id)
    evaluate_target_health = var.domain_config.evaluate_target_health
  }

  provider = aws.dns
}