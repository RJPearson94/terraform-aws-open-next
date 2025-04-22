locals {
  prefix = var.prefix == null ? "" : "${var.prefix}-"
  suffix = var.suffix == null ? "" : "-${var.suffix}"

  s3_origin_id                       = "s3-origin"
  image_optimisation_function_origin = "image-optimisation-function-origin"
  server_function_origin             = "server-function-origin"

  create_cache_policy = try(var.cache_policy.deployment, "CREATE") == "CREATE"
  cache_policy_id     = local.create_cache_policy ? one(aws_cloudfront_cache_policy.cache_policy[*].id) : try(var.cache_policy.id, null)
  
  create_response_headers    = try(var.response_headers.deployment, "NONE") == "CREATE"
  response_headers_policy_id = local.create_response_headers ? one(aws_cloudfront_response_headers_policy.response_headers[*].id) : try(var.response_headers.id, null)

  cache_keys = {
    v2 = ["accept", "rsc", "next-router-prefetch", "next-router-state-tree", "next-url", "x-prerender-bypass", "x-prerender-revalidate"]
    v3 = ["x-open-next-cache-key"]
  }

  cloudfront_function_code = {
    v2 = "xForwardedHost.js",
    v3 = "cloudfrontFunctionOpenNextV3.js"
  }

  should_create_auth_lambda    = contains(["DETACH", "CREATE"], var.auth_function.deployment) || (var.auth_function.deployment != "USE_EXISTING" && length({ for zone in local.zones : "${zone.name}-distribution" => zone if anytrue([for origin in zone.origins : origin.auth == "AUTH_LAMBDA"]) }) > 0)
  should_create_lambda_url_oac = var.lambda_url_oac.deployment == "CREATE" || length({ for zone in local.zones : "${zone.name}-distribution" => zone if anytrue([for origin in zone.origins : origin.auth == "OAC"]) }) > 0
  auth_lambda_qualified_arn    = var.auth_function.deployment == "USE_EXISTING" ? var.auth_function.qualified_arn : local.should_create_auth_lambda ? one(module.auth_function[*].qualified_arn) : null

  custom_error_responses        = [for custom_error_response in var.custom_error_responses : merge(custom_error_response, { path_pattern = "/${custom_error_response.response_page.behaviour}/*" }) if custom_error_response.response_page != null]
  includes_staging_distribution = var.continuous_deployment.use && var.continuous_deployment.deployment != "NONE"

  # Force the root zone to the bottom of the behaviours
  zones      = concat([for zone in var.zones : merge(zone, { path_prefix = "/${coalesce(zone.path, zone.name)}" }) if zone.root == false], [for zone in var.zones : merge(zone, { path_prefix = zone.path != null ? "/${zone.path}" : "" }) if zone.root == true])
  root_zones = [for zone in local.zones : zone if zone.root == true][0]

  # Ensure bucket name stays within 64 character limit. If name exceeds limit, truncate and add a hash suffix for uniqueness
  full_origin_access_control_name  = "${local.prefix}website-bucket${local.suffix}"
  valid_origin_access_control_name = length(local.full_origin_access_control_name) > 64 ? "${substr(local.full_origin_access_control_name, 0, 58)}-${substr(sha1(local.full_origin_access_control_name), 0, 5)}" : local.full_origin_access_control_name

  ordered_cache_behaviors = concat(
    [
      for custom_error_response in local.custom_error_responses : {
        path_pattern     = custom_error_response.path_pattern
        allowed_methods  = coalesce(try(var.behaviours.custom_error_responses.path_overrides[custom_error_response.path_pattern].allowed_methods, null), try(var.behaviours.custom_error_responses.allowed_methods, null), ["GET", "HEAD", "OPTIONS"])
        cached_methods   = coalesce(try(var.behaviours.custom_error_responses.path_overrides[custom_error_response.path_pattern].cached_methods, null), try(var.behaviours.custom_error_responses.cached_methods, null), ["GET", "HEAD", "OPTIONS"])
        target_origin_id = join("-", compact([custom_error_response.error_code, local.s3_origin_id]))

        cache_policy_id          = coalesce(try(var.behaviours.custom_error_responses.path_overrides[custom_error_response.path_pattern].cache_policy_id, null), try(var.behaviours.custom_error_responses.cache_policy_id, null), data.aws_cloudfront_cache_policy.caching_optimized.id)
        realtime_log_config_arn  = coalesce(try(var.behaviours.custom_error_responses.path_overrides[custom_error_response.path_pattern].realtime_log_config_arn, null), try(var.behaviours.custom_error_responses.realtime_log_config_arn, null))
        origin_request_policy_id = try(coalesce(try(var.behaviours.custom_error_responses.path_overrides[custom_error_response.path_pattern].origin_request_policy_id, null), try(var.behaviours.custom_error_responses.origin_request_policy_id, null)), null)

        response_headers_policy_id = try(coalesce(try(var.behaviours.custom_error_responses.path_overrides[custom_error_response.path_pattern].response_headers_policy_id, null), try(var.behaviours.custom_error_responses.response_headers_policy_id, null), local.response_headers_policy_id), null)

        compress               = coalesce(try(var.behaviours.custom_error_responses.path_overrides[custom_error_response.path_pattern].compress, null), try(var.behaviours.custom_error_responses.compress, null), true)
        viewer_protocol_policy = coalesce(try(var.behaviours.custom_error_responses.path_overrides[custom_error_response.path_pattern].viewer_protocol_policy, null), try(var.behaviours.custom_error_responses.viewer_protocol_policy, null), "redirect-to-https")

        function_associations = [
          merge(coalesce(try(var.behaviours.custom_error_responses.path_overrides[custom_error_response.path_pattern].viewer_request, null), try(var.behaviours.custom_error_responses.viewer_request, null), { type = "CLOUDFRONT_FUNCTION", arn = null }), { event_type = "viewer-request" }),
          merge(coalesce(try(var.behaviours.custom_error_responses.path_overrides[custom_error_response.path_pattern].viewer_response, null), try(var.behaviours.custom_error_responses.viewer_response, null), { type = "CLOUDFRONT_FUNCTION", arn = null }), { event_type = "viewer-response" }),
        ]

        lambda_function_associations = [
          merge(coalesce(try(var.behaviours.custom_error_responses.path_overrides[custom_error_response.path_pattern].viewer_request, null), try(var.behaviours.custom_error_responses.viewer_request, null), { type = "LAMBDA@EDGE", arn = null }), { event_type = "viewer-request" }),
          merge(coalesce(try(var.behaviours.custom_error_responses.path_overrides[custom_error_response.path_pattern].viewer_response, null), try(var.behaviours.custom_error_responses.viewer_response, null), { type = "LAMBDA@EDGE", arn = null }), { event_type = "viewer-response" }),
          merge(coalesce(try(var.behaviours.custom_error_responses.path_overrides[custom_error_response.path_pattern].origin_request, null), try(var.behaviours.custom_error_responses.origin_request, null), { arn = null }), { type = "LAMBDA@EDGE", event_type = "origin-request" }),
          merge(coalesce(try(var.behaviours.custom_error_responses.path_overrides[custom_error_response.path_pattern].origin_response, null), try(var.behaviours.custom_error_responses.origin_response, null), { arn = null }), { type = "LAMBDA@EDGE", event_type = "origin-response" }),
        ]
      }
    ],
    flatten([
      for zone in local.zones : concat(
        [for index, image_optimisation_behaviour in lookup(zone.origins, "image_optimisation", null) == null ? [] : [for path in coalesce(try(var.behaviours.image_optimisation.zone_overrides[zone.name].paths, null), try(var.behaviours.image_optimisation.paths, null), ["/_next/image"]) : startswith(path, zone.path_prefix) ? { original : path, formatted : path } : { original : path, formatted : format("%s%s", zone.path_prefix, path) }] : {
          path_pattern     = image_optimisation_behaviour.formatted
          allowed_methods  = coalesce(try(var.behaviours.image_optimisation.path_overrides[image_optimisation_behaviour.formatted].allowed_methods, null), try(var.behaviours.image_optimisation.zone_overrides[zone.name].path_overrides[image_optimisation_behaviour.original].allowed_methods, null), try(var.behaviours.image_optimisation.zone_overrides[zone.name].allowed_methods, null), try(var.behaviours.image_optimisation.allowed_methods, null), ["GET", "HEAD", "OPTIONS", "PUT", "PATCH", "POST", "DELETE"])
          cached_methods   = coalesce(try(var.behaviours.image_optimisation.path_overrides[image_optimisation_behaviour.formatted].cached_methods, null), try(var.behaviours.image_optimisation.zone_overrides[zone.name].path_overrides[image_optimisation_behaviour.original].cached_methods, null), try(var.behaviours.image_optimisation.zone_overrides[zone.name].cached_methods, null), try(var.behaviours.image_optimisation.cached_methods, null), ["GET", "HEAD", "OPTIONS"])
          target_origin_id = join("-", compact([zone.name, local.image_optimisation_function_origin]))

          cache_policy_id          = coalesce(try(var.behaviours.image_optimisation.path_overrides[image_optimisation_behaviour.formatted].cache_policy_id, null), try(var.behaviours.image_optimisation.zone_overrides[zone.name].path_overrides[image_optimisation_behaviour.original].cache_policy_id, null), try(var.behaviours.image_optimisation.zone_overrides[zone.name].cache_policy_id, null), try(var.behaviours.image_optimisation.cache_policy_id, null), local.cache_policy_id)
          realtime_log_config_arn  = coalesce(try(var.behaviours.image_optimisation.path_overrides[image_optimisation_behaviour.formatted].realtime_log_config_arn, null), try(var.behaviours.image_optimisation.zone_overrides[zone.name].path_overrides[image_optimisation_behaviour.original].realtime_log_config_arn, null), try(var.behaviours.image_optimisation.zone_overrides[zone.name].realtime_log_config_arn, null), try(var.behaviours.image_optimisation.realtime_log_config_arn, null))
          origin_request_policy_id = coalesce(try(var.behaviours.image_optimisation.path_overrides[image_optimisation_behaviour.formatted].origin_request_policy_id, null), try(var.behaviours.image_optimisation.zone_overrides[zone.name].path_overrides[image_optimisation_behaviour.original].origin_request_policy_id, null), try(var.behaviours.image_optimisation.zone_overrides[zone.name].origin_request_policy_id, null), try(var.behaviours.image_optimisation.origin_request_policy_id, null), data.aws_cloudfront_origin_request_policy.all_viewer_except_host_header.id)

          response_headers_policy_id = try(coalesce(try(var.behaviours.image_optimisation.path_overrides[image_optimisation_behaviour.formatted].response_headers_policy_id, null), try(var.behaviours.image_optimisation.zone_overrides[zone.name].path_overrides[image_optimisation_behaviour.original].response_headers_policy_id, null), try(var.behaviours.image_optimisation.zone_overrides[zone.name].response_headers_policy_id, null), try(var.behaviours.image_optimisation.response_headers_policy_id, null), local.response_headers_policy_id), null)

          compress               = coalesce(try(var.behaviours.image_optimisation.path_overrides[image_optimisation_behaviour.formatted].compress, null), try(var.behaviours.image_optimisation.zone_overrides[zone.name].path_overrides[image_optimisation_behaviour.original].compress, null), try(var.behaviours.image_optimisation.zone_overrides[zone.name].compress, null), try(var.behaviours.image_optimisation.compress, null), true)
          viewer_protocol_policy = coalesce(try(var.behaviours.image_optimisation.path_overrides[image_optimisation_behaviour.formatted].viewer_protocol_policy, null), try(var.behaviours.image_optimisation.zone_overrides[zone.name].path_overrides[image_optimisation_behaviour.original].viewer_protocol_policy, null), try(var.behaviours.image_optimisation.zone_overrides[zone.name].viewer_protocol_policy, null), try(var.behaviours.image_optimisation.viewer_protocol_policy, null), "redirect-to-https")

          function_associations = [
            merge(coalesce(try(var.behaviours.image_optimisation.path_overrides[image_optimisation_behaviour.formatted].viewer_request, null), try(var.behaviours.image_optimisation.zone_overrides[zone.name].path_overrides[image_optimisation_behaviour.original].viewer_request, null), try(var.behaviours.image_optimisation.zone_overrides[zone.name].viewer_request, null), try(var.behaviours.image_optimisation.viewer_request, null), { type = "CLOUDFRONT_FUNCTION", arn = null }), { event_type = "viewer-request" }),
            merge(coalesce(try(var.behaviours.image_optimisation.path_overrides[image_optimisation_behaviour.formatted].viewer_response, null), try(var.behaviours.image_optimisation.zone_overrides[zone.name].path_overrides[image_optimisation_behaviour.original].viewer_response, null), try(var.behaviours.image_optimisation.zone_overrides[zone.name].viewer_response, null), try(var.behaviours.image_optimisation.viewer_response, null), { type = "CLOUDFRONT_FUNCTION", arn = null }), { event_type = "viewer-response" }),
          ]

          lambda_function_associations = [
            merge(coalesce(try(var.behaviours.image_optimisation.path_overrides[image_optimisation_behaviour.formatted].viewer_request, null), try(var.behaviours.image_optimisation.zone_overrides[zone.name].path_overrides[image_optimisation_behaviour.original].viewer_request, null), try(var.behaviours.image_optimisation.zone_overrides[zone.name].viewer_request, null), try(var.behaviours.image_optimisation.viewer_request, null), { type = "LAMBDA@EDGE", arn = null }), { event_type = "viewer-request" }),
            merge(coalesce(try(var.behaviours.image_optimisation.path_overrides[image_optimisation_behaviour.formatted].viewer_response, null), try(var.behaviours.image_optimisation.zone_overrides[zone.name].path_overrides[image_optimisation_behaviour.original].viewer_response, null), try(var.behaviours.image_optimisation.zone_overrides[zone.name].viewer_response, null), try(var.behaviours.image_optimisation.viewer_response, null), { type = "LAMBDA@EDGE", arn = null }), { event_type = "viewer-response" }),
            merge(coalesce(try(var.behaviours.image_optimisation.path_overrides[image_optimisation_behaviour.formatted].origin_request, null), try(var.behaviours.image_optimisation.zone_overrides[zone.name].path_overrides[image_optimisation_behaviour.original].origin_request, null), try(var.behaviours.image_optimisation.zone_overrides[zone.name].origin_request, null), try(var.behaviours.image_optimisation.origin_request, null), { arn = zone.origins["image_optimisation"].auth == "AUTH_LAMBDA" ? local.auth_lambda_qualified_arn : null, include_body = true }), { type = "LAMBDA@EDGE", event_type = "origin-request" }),
            merge(coalesce(try(var.behaviours.image_optimisation.path_overrides[image_optimisation_behaviour.formatted].origin_response, null), try(var.behaviours.image_optimisation.zone_overrides[zone.name].path_overrides[image_optimisation_behaviour.original].origin_response, null), try(var.behaviours.image_optimisation.zone_overrides[zone.name].origin_response, null), try(var.behaviours.image_optimisation.origin_response, null), { arn = null }), { type = "LAMBDA@EDGE", event_type = "origin-response" }),
          ]
        }],
        flatten([for name, origin in var.behaviours.additional_origins : [for index, additional_origin_behaviour in [for path in try(coalesce(try(origin.zone_overrides[zone.name].paths, null), origin.paths), []) : startswith(path, zone.path_prefix) ? path : format("%s%s", zone.path_prefix, path)] : {
          path_pattern     = additional_origin_behaviour
          allowed_methods  = coalesce(try(origin.path_overrides[additional_origin_behaviour].allowed_methods, null), try(origin.allowed_methods, null), ["GET", "HEAD", "OPTIONS", "PUT", "PATCH", "POST", "DELETE"])
          cached_methods   = coalesce(try(origin.path_overrides[additional_origin_behaviour].cached_methods, null), try(origin.cached_methods, null), ["GET", "HEAD", "OPTIONS"])
          target_origin_id = lookup(zone.origins, name, null) == null ? join("-", compact([zone.name, local.s3_origin_id])) : join("-", compact([zone.name, "${name}-function"]))

          cache_policy_id          = coalesce(try(origin.path_overrides[additional_origin_behaviour].cache_policy_id, null), try(origin.cache_policy_id, null), local.cache_policy_id)
          realtime_log_config_arn  = coalesce(try(origin.path_overrides[additional_origin_behaviour].realtime_log_config_arn, null), try(origin.realtime_log_config_arn, null))
          origin_request_policy_id = coalesce(try(origin.path_overrides[additional_origin_behaviour].origin_request_policy_id, null), try(origin.origin_request_policy_id, null), data.aws_cloudfront_origin_request_policy.all_viewer_except_host_header.id)

          response_headers_policy_id = try(coalesce(try(origin.path_overrides[additional_origin_behaviour].response_headers_policy_id, null), try(origin.response_headers_policy_id, null), local.response_headers_policy_id), null)

          compress               = coalesce(try(origin.path_overrides[additional_origin_behaviour].compress, null), try(origin.compress, null), true)
          viewer_protocol_policy = coalesce(try(origin.path_overrides[additional_origin_behaviour].viewer_protocol_policy, null), try(origin.viewer_protocol_policy, null), "redirect-to-https")

          function_associations = [
            merge(coalesce(try(origin.path_overrides[additional_origin_behaviour].viewer_request, null), try(origin.viewer_request, null), { type = "CLOUDFRONT_FUNCTION", arn = aws_cloudfront_function.x_forwarded_host.arn }), { event_type = "viewer-request" }),
            merge(coalesce(try(origin.path_overrides[additional_origin_behaviour].viewer_response, null), try(origin.viewer_response, null), { type = "CLOUDFRONT_FUNCTION", arn = null }), { event_type = "viewer-response" }),
          ]

          lambda_function_associations = [
            merge(coalesce(try(origin.path_overrides[additional_origin_behaviour].viewer_request, null), try(origin.viewer_request, null), { type = "LAMBDA@EDGE", arn = null }), { event_type = "viewer-request" }),
            merge(coalesce(try(origin.path_overrides[additional_origin_behaviour].viewer_response, null), try(origin.viewer_response, null), { type = "LAMBDA@EDGE", arn = null }), { event_type = "viewer-response" }),
            merge(coalesce(try(origin.path_overrides[additional_origin_behaviour].origin_request, null), try(origin.origin_request, null), { arn = zone.origins[name].auth == "AUTH_LAMBDA" ? local.auth_lambda_qualified_arn : null, include_body = true }), { type = "LAMBDA@EDGE", event_type = "origin-request" }),
            merge(coalesce(try(origin.path_overrides[additional_origin_behaviour].origin_response, null), try(origin.origin_response, null), { arn = null }), { type = "LAMBDA@EDGE", event_type = "origin-response" }),
          ]
          }] if lookup(zone.origins, name, null) != null
        ]),
        [for index, server_behaviour in [for path in coalesce(try(var.behaviours.server.zone_overrides[zone.name].paths, null), try(var.behaviours.server.paths, null), ["/_next/data/*", "/api/*"]) : startswith(path, zone.path_prefix) ? { original : path, formatted : path } : { original : path, formatted : format("%s%s", zone.path_prefix, path) } if path != "*"] : {
          path_pattern     = server_behaviour.formatted
          allowed_methods  = coalesce(try(var.behaviours.server.path_overrides[server_behaviour.formatted].allowed_methods, null), try(var.behaviours.server.zone_overrides[zone.name].path_overrides[server_behaviour.original].allowed_methods, null), try(var.behaviours.server.zone_overrides[zone.name].allowed_methods, null), try(var.behaviours.server.allowed_methods, null), ["GET", "HEAD", "OPTIONS", "PUT", "PATCH", "POST", "DELETE"])
          cached_methods   = coalesce(try(var.behaviours.server.path_overrides[server_behaviour.formatted].cached_methods, null), try(var.behaviours.server.zone_overrides[zone.name].path_overrides[server_behaviour.original].cached_methods, null), try(var.behaviours.server.zone_overrides[zone.name].cached_methods, null), try(var.behaviours.server.cached_methods, null), ["GET", "HEAD", "OPTIONS"])
          target_origin_id = lookup(zone.origins, "server", null) == null ? join("-", compact([zone.name, local.s3_origin_id])) : join("-", compact([zone.name, local.server_function_origin]))

          cache_policy_id          = coalesce(try(var.behaviours.server.path_overrides[server_behaviour.formatted].cache_policy_id, null), try(var.behaviours.server.zone_overrides[zone.name].path_overrides[server_behaviour.original].cache_policy_id, null), try(var.behaviours.server.zone_overrides[zone.name].cache_policy_id, null), try(var.behaviours.server.cache_policy_id, null), local.cache_policy_id)
          realtime_log_config_arn  = coalesce(try(var.behaviours.server.path_overrides[server_behaviour.formatted].realtime_log_config_arn, null), try(var.behaviours.server.zone_overrides[zone.name].path_overrides[server_behaviour.original].realtime_log_config_arn, null), try(var.behaviours.server.zone_overrides[zone.name].realtime_log_config_arn, null), try(var.behaviours.server.realtime_log_config_arn, null))
          origin_request_policy_id = coalesce(try(var.behaviours.server.path_overrides[server_behaviour.formatted].origin_request_policy_id, null), try(var.behaviours.server.zone_overrides[zone.name].path_overrides[server_behaviour.original].origin_request_policy_id, null), try(var.behaviours.server.zone_overrides[zone.name].origin_request_policy_id, null), try(var.behaviours.server.origin_request_policy_id, null), data.aws_cloudfront_origin_request_policy.all_viewer_except_host_header.id)

          response_headers_policy_id = try(coalesce(try(var.behaviours.server.path_overrides[server_behaviour.formatted].response_headers_policy_id, null), try(var.behaviours.server.zone_overrides[zone.name].path_overrides[server_behaviour.original].response_headers_policy_id, null), try(var.behaviours.server.zone_overrides[zone.name].response_headers_policy_id, null), try(var.behaviours.server.response_headers_policy_id, null), local.response_headers_policy_id), null)

          compress               = coalesce(try(var.behaviours.server.path_overrides[server_behaviour.formatted].compress, null), try(var.behaviours.server.zone_overrides[zone.name].path_overrides[server_behaviour.original].compress, null), try(var.behaviours.server.zone_overrides[zone.name].compress, null), try(var.behaviours.server.compress, null), true)
          viewer_protocol_policy = coalesce(try(var.behaviours.server.path_overrides[server_behaviour.formatted].viewer_protocol_policy, null), try(var.behaviours.server.zone_overrides[zone.name].path_overrides[server_behaviour.original].viewer_protocol_policy, null), try(var.behaviours.server.zone_overrides[zone.name].viewer_protocol_policy, null), try(var.behaviours.server.viewer_protocol_policy, null), "redirect-to-https")

          function_associations = [
            merge(coalesce(try(var.behaviours.server.path_overrides[server_behaviour.formatted].viewer_request, null), try(var.behaviours.server.zone_overrides[zone.name].path_overrides[server_behaviour.original].viewer_request, null), try(var.behaviours.server.zone_overrides[zone.name].viewer_request, null), try(var.behaviours.server.viewer_request, null), { type = "CLOUDFRONT_FUNCTION", arn = aws_cloudfront_function.x_forwarded_host.arn }), { event_type = "viewer-request" }),
            merge(coalesce(try(var.behaviours.server.path_overrides[server_behaviour.formatted].viewer_response, null), try(var.behaviours.server.zone_overrides[zone.name].path_overrides[server_behaviour.original].viewer_response, null), try(var.behaviours.server.zone_overrides[zone.name].viewer_response, null), try(var.behaviours.server.viewer_response, null), { type = "CLOUDFRONT_FUNCTION", arn = null }), { event_type = "viewer-response" }),
          ]

          lambda_function_associations = [
            merge(coalesce(try(var.behaviours.server.path_overrides[server_behaviour.formatted].viewer_request, null), try(var.behaviours.server.zone_overrides[zone.name].path_overrides[server_behaviour.original].viewer_request, null), try(var.behaviours.server.zone_overrides[zone.name].viewer_request, null), try(var.behaviours.server.viewer_request, null), { type = "LAMBDA@EDGE", arn = null }), { event_type = "viewer-request" }),
            merge(coalesce(try(var.behaviours.server.path_overrides[server_behaviour.formatted].viewer_response, null), try(var.behaviours.server.zone_overrides[zone.name].path_overrides[server_behaviour.original].viewer_response, null), try(var.behaviours.server.zone_overrides[zone.name].viewer_response, null), try(var.behaviours.server.viewer_response, null), { type = "LAMBDA@EDGE", arn = null }), { event_type = "viewer-response" }),
            merge(coalesce(try(var.behaviours.server.path_overrides[server_behaviour.formatted].origin_request, null), try(var.behaviours.server.zone_overrides[zone.name].path_overrides[server_behaviour.original].origin_request, null), try(var.behaviours.server.zone_overrides[zone.name].origin_request, null), try(var.behaviours.server.origin_request, null), { arn = try(zone.origins["server"].auth, null) == "AUTH_LAMBDA" ? local.auth_lambda_qualified_arn : null, include_body = true }), { type = "LAMBDA@EDGE", event_type = "origin-request" }),
            merge(coalesce(try(var.behaviours.server.path_overrides[server_behaviour.formatted].origin_response, null), try(var.behaviours.server.zone_overrides[zone.name].path_overrides[server_behaviour.original].origin_response, null), try(var.behaviours.server.zone_overrides[zone.name].origin_response, null), try(var.behaviours.server.origin_response, null), { arn = null }), { type = "LAMBDA@EDGE", event_type = "origin-response" }),
          ]
        }],
        [for index, static_assets_behaviour in [for path in coalesce(try(var.behaviours.static_assets.zone_overrides[zone.name].paths, null), try(var.behaviours.static_assets.paths, null), concat(["/_next/static/*"], coalesce(try(var.behaviours.static_assets.zone_overrides[zone.name].additional_paths, null), try(var.behaviours.static_assets.additional_paths, null), []))) : startswith(path, zone.path_prefix) ? { original : path, formatted : path } : { original : path, formatted : format("%s%s", zone.path_prefix, path) }] : {
          path_pattern     = static_assets_behaviour.formatted
          allowed_methods  = coalesce(try(var.behaviours.static_assets.path_overrides[static_assets_behaviour.formatted].allowed_methods, null), try(var.behaviours.static_assets.zone_overrides[zone.name].path_overrides[static_assets_behaviour.original].allowed_methods, null), try(var.behaviours.static_assets.zone_overrides[zone.name].allowed_methods, null), try(var.behaviours.static_assets.allowed_methods, null), ["GET", "HEAD", "OPTIONS"])
          cached_methods   = coalesce(try(var.behaviours.static_assets.path_overrides[static_assets_behaviour.formatted].cached_methods, null), try(var.behaviours.static_assets.zone_overrides[zone.name].path_overrides[static_assets_behaviour.original].cached_methods, null), try(var.behaviours.static_assets.zone_overrides[zone.name].cached_methods, null), try(var.behaviours.static_assets.cached_methods, null), ["GET", "HEAD", "OPTIONS"])
          target_origin_id = join("-", compact([zone.name, local.s3_origin_id]))

          cache_policy_id          = coalesce(try(var.behaviours.static_assets.path_overrides[static_assets_behaviour.formatted].cache_policy_id, null), try(var.behaviours.static_assets.zone_overrides[zone.name].path_overrides[static_assets_behaviour.original].cache_policy_id, null), try(var.behaviours.static_assets.zone_overrides[zone.name].cache_policy_id, null), try(var.behaviours.static_assets.cache_policy_id, null), data.aws_cloudfront_cache_policy.caching_optimized.id)
          realtime_log_config_arn  = coalesce(try(var.behaviours.static_assets.path_overrides[static_assets_behaviour.formatted].realtime_log_config_arn, null), try(var.behaviours.static_assets.zone_overrides[zone.name].path_overrides[static_assets_behaviour.original].realtime_log_config_arn, null), try(var.behaviours.static_assets.zone_overrides[zone.name].realtime_log_config_arn, null), try(var.behaviours.static_assets.realtime_log_config_arn, null))
          origin_request_policy_id = try(coalesce(try(var.behaviours.static_assets.path_overrides[static_assets_behaviour.formatted].origin_request_policy_id, null), try(var.behaviours.static_assets.zone_overrides[zone.name].path_overrides[static_assets_behaviour.original].origin_request_policy_id, null), try(var.behaviours.static_assets.zone_overrides[zone.name].origin_request_policy_id, null), try(var.behaviours.static_assets.origin_request_policy_id, null)), null)

          response_headers_policy_id = try(coalesce(try(var.behaviours.static_assets.path_overrides[static_assets_behaviour.formatted].response_headers_policy_id, null), try(var.behaviours.static_assets.zone_overrides[zone.name].path_overrides[static_assets_behaviour.original].response_headers_policy_id, null), try(var.behaviours.static_assets.zone_overrides[zone.name].response_headers_policy_id, null), try(var.behaviours.static_assets.response_headers_policy_id, null), local.response_headers_policy_id), null)

          compress               = coalesce(try(var.behaviours.static_assets.path_overrides[static_assets_behaviour.formatted].compress, null), try(var.behaviours.static_assets.zone_overrides[zone.name].path_overrides[static_assets_behaviour.original].compress, null), try(var.behaviours.static_assets.zone_overrides[zone.name].compress, null), try(var.behaviours.static_assets.compress, null), true)
          viewer_protocol_policy = coalesce(try(var.behaviours.static_assets.path_overrides[static_assets_behaviour.formatted].viewer_protocol_policy, null), try(var.behaviours.static_assets.zone_overrides[zone.name].path_overrides[static_assets_behaviour.original].viewer_protocol_policy, null), try(var.behaviours.static_assets.zone_overrides[zone.name].viewer_protocol_policy, null), try(var.behaviours.static_assets.viewer_protocol_policy, null), "redirect-to-https")

          function_associations = [
            merge(coalesce(try(var.behaviours.static_assets.path_overrides[static_assets_behaviour.formatted].viewer_request, null), try(var.behaviours.static_assets.zone_overrides[zone.name].path_overrides[static_assets_behaviour.original].viewer_request, null), try(var.behaviours.static_assets.zone_overrides[zone.name].viewer_request, null), try(var.behaviours.static_assets.viewer_request, null), { type = "CLOUDFRONT_FUNCTION", arn = null }), { event_type = "viewer-request" }),
            merge(coalesce(try(var.behaviours.static_assets.path_overrides[static_assets_behaviour.formatted].viewer_response, null), try(var.behaviours.static_assets.zone_overrides[zone.name].path_overrides[static_assets_behaviour.original].viewer_response, null), try(var.behaviours.static_assets.zone_overrides[zone.name].viewer_response, null), try(var.behaviours.static_assets.viewer_response, null), { type = "CLOUDFRONT_FUNCTION", arn = null }), { event_type = "viewer-response" }),
          ]

          lambda_function_associations = [
            merge(coalesce(try(var.behaviours.static_assets.path_overrides[static_assets_behaviour.formatted].viewer_request, null), try(var.behaviours.static_assets.zone_overrides[zone.name].path_overrides[static_assets_behaviour.original].viewer_request, null), try(var.behaviours.static_assets.zone_overrides[zone.name].viewer_request, null), try(var.behaviours.static_assets.viewer_request, null), { type = "LAMBDA@EDGE", arn = null }), { event_type = "viewer-request" }),
            merge(coalesce(try(var.behaviours.static_assets.path_overrides[static_assets_behaviour.formatted].viewer_response, null), try(var.behaviours.static_assets.zone_overrides[zone.name].path_overrides[static_assets_behaviour.original].viewer_response, null), try(var.behaviours.static_assets.zone_overrides[zone.name].viewer_response, null), try(var.behaviours.static_assets.viewer_response, null), { type = "LAMBDA@EDGE", arn = null }), { event_type = "viewer-response" }),
            merge(coalesce(try(var.behaviours.static_assets.path_overrides[static_assets_behaviour.formatted].origin_request, null), try(var.behaviours.static_assets.zone_overrides[zone.name].path_overrides[static_assets_behaviour.original].origin_request, null), try(var.behaviours.static_assets.zone_overrides[zone.name].origin_request, null), try(var.behaviours.static_assets.origin_request, null), { arn = null }), { type = "LAMBDA@EDGE", event_type = "origin-request" }),
            merge(coalesce(try(var.behaviours.static_assets.path_overrides[static_assets_behaviour.formatted].origin_response, null), try(var.behaviours.static_assets.zone_overrides[zone.name].path_overrides[static_assets_behaviour.original].origin_response, null), try(var.behaviours.static_assets.zone_overrides[zone.name].origin_response, null), try(var.behaviours.static_assets.origin_response, null), { arn = null }), { type = "LAMBDA@EDGE", event_type = "origin-response" }),
          ]
          }
        ],
        [for index, server_behaviour in [for path in coalesce(try(var.behaviours.server.zone_overrides[zone.name].paths, null), try(var.behaviours.server.paths, null), ["*"]) : startswith(path, zone.path_prefix) ? { original : path, formatted : path } : { original : path, formatted : format("%s%s", zone.path_prefix, path) } if path == "*"] : {
          path_pattern     = server_behaviour.formatted
          allowed_methods  = coalesce(try(var.behaviours.server.path_overrides[server_behaviour.formatted].allowed_methods, null), try(var.behaviours.server.zone_overrides[zone.name].path_overrides[server_behaviour.original].allowed_methods, null), try(var.behaviours.server.zone_overrides[zone.name].allowed_methods, null), try(var.behaviours.server.allowed_methods, null), ["GET", "HEAD", "OPTIONS", "PUT", "PATCH", "POST", "DELETE"])
          cached_methods   = coalesce(try(var.behaviours.server.path_overrides[server_behaviour.formatted].cached_methods, null), try(var.behaviours.server.zone_overrides[zone.name].path_overrides[server_behaviour.original].cached_methods, null), try(var.behaviours.server.zone_overrides[zone.name].cached_methods, null), try(var.behaviours.server.cached_methods, null), ["GET", "HEAD", "OPTIONS"])
          target_origin_id = lookup(zone.origins, "server", null) == null ? join("-", compact([zone.name, local.s3_origin_id])) : join("-", compact([zone.name, local.server_function_origin]))

          cache_policy_id          = coalesce(try(var.behaviours.server.path_overrides[server_behaviour.formatted].cache_policy_id, null), try(var.behaviours.server.zone_overrides[zone.name].path_overrides[server_behaviour.original].cache_policy_id, null), try(var.behaviours.server.zone_overrides[zone.name].cache_policy_id, null), try(var.behaviours.server.cache_policy_id, null), local.cache_policy_id)
          realtime_log_config_arn  = coalesce(try(var.behaviours.server.path_overrides[server_behaviour.formatted].realtime_log_config_arn, null), try(var.behaviours.server.zone_overrides[zone.name].path_overrides[server_behaviour.original].realtime_log_config_arn, null), try(var.behaviours.server.zone_overrides[zone.name].realtime_log_config_arn, null), try(var.behaviours.server.realtime_log_config_arn, null))
          origin_request_policy_id = coalesce(try(var.behaviours.server.path_overrides[server_behaviour.formatted].origin_request_policy_id, null), try(var.behaviours.server.zone_overrides[zone.name].path_overrides[server_behaviour.original].origin_request_policy_id, null), try(var.behaviours.server.zone_overrides[zone.name].origin_request_policy_id, null), try(var.behaviours.server.origin_request_policy_id, null), data.aws_cloudfront_origin_request_policy.all_viewer_except_host_header.id)

          response_headers_policy_id = try(coalesce(try(var.behaviours.server.path_overrides[server_behaviour.formatted].response_headers_policy_id, null), try(var.behaviours.server.zone_overrides[zone.name].path_overrides[server_behaviour.original].response_headers_policy_id, null), try(var.behaviours.server.zone_overrides[zone.name].response_headers_policy_id, null), try(var.behaviours.server.response_headers_policy_id, null), local.response_headers_policy_id), null)

          compress               = coalesce(try(var.behaviours.server.path_overrides[server_behaviour.formatted].compress, null), try(var.behaviours.server.zone_overrides[zone.name].path_overrides[server_behaviour.original].compress, null), try(var.behaviours.server.zone_overrides[zone.name].compress, null), try(var.behaviours.server.compress, null), true)
          viewer_protocol_policy = coalesce(try(var.behaviours.server.path_overrides[server_behaviour.formatted].viewer_protocol_policy, null), try(var.behaviours.server.zone_overrides[zone.name].path_overrides[server_behaviour.original].viewer_protocol_policy, null), try(var.behaviours.server.zone_overrides[zone.name].viewer_protocol_policy, null), try(var.behaviours.server.viewer_protocol_policy, null), "redirect-to-https")

          function_associations = [
            merge(coalesce(try(var.behaviours.server.path_overrides[server_behaviour.formatted].viewer_request, null), try(var.behaviours.server.zone_overrides[zone.name].path_overrides[server_behaviour.original].viewer_request, null), try(var.behaviours.server.zone_overrides[zone.name].viewer_request, null), try(var.behaviours.server.viewer_request, null), { type = "CLOUDFRONT_FUNCTION", arn = aws_cloudfront_function.x_forwarded_host.arn }), { event_type = "viewer-request" }),
            merge(coalesce(try(var.behaviours.server.path_overrides[server_behaviour.formatted].viewer_response, null), try(var.behaviours.server.zone_overrides[zone.name].path_overrides[server_behaviour.original].viewer_response, null), try(var.behaviours.server.zone_overrides[zone.name].viewer_response, null), try(var.behaviours.server.viewer_response, null), { type = "CLOUDFRONT_FUNCTION", arn = null }), { event_type = "viewer-response" }),
          ]

          lambda_function_associations = [
            merge(coalesce(try(var.behaviours.server.path_overrides[server_behaviour.formatted].viewer_request, null), try(var.behaviours.server.zone_overrides[zone.name].path_overrides[server_behaviour.original].viewer_request, null), try(var.behaviours.server.zone_overrides[zone.name].viewer_request, null), try(var.behaviours.server.viewer_request, null), { type = "LAMBDA@EDGE", arn = null }), { event_type = "viewer-request" }),
            merge(coalesce(try(var.behaviours.server.path_overrides[server_behaviour.formatted].viewer_response, null), try(var.behaviours.server.zone_overrides[zone.name].path_overrides[server_behaviour.original].viewer_response, null), try(var.behaviours.server.zone_overrides[zone.name].viewer_response, null), try(var.behaviours.server.viewer_response, null), { type = "LAMBDA@EDGE", arn = null }), { event_type = "viewer-response" }),
            merge(coalesce(try(var.behaviours.server.path_overrides[server_behaviour.formatted].origin_request, null), try(var.behaviours.server.zone_overrides[zone.name].path_overrides[server_behaviour.original].origin_request, null), try(var.behaviours.server.zone_overrides[zone.name].origin_request, null), try(var.behaviours.server.origin_request, null), { arn = try(zone.origins["server"].auth, null) == "AUTH_LAMBDA" ? local.auth_lambda_qualified_arn : null, include_body = true }), { type = "LAMBDA@EDGE", event_type = "origin-request" }),
            merge(coalesce(try(var.behaviours.server.path_overrides[server_behaviour.formatted].origin_response, null), try(var.behaviours.server.zone_overrides[zone.name].path_overrides[server_behaviour.original].origin_response, null), try(var.behaviours.server.zone_overrides[zone.name].origin_response, null), try(var.behaviours.server.origin_response, null), { arn = null }), { type = "LAMBDA@EDGE", event_type = "origin-response" }),
          ]
        }],
      )
    ])
  )

  origins = concat(
    [
      for custom_error_response in local.custom_error_responses : {
        domain_name              = custom_error_response.bucket_domain_name
        origin_access_control_id = aws_cloudfront_origin_access_control.website_origin_access_control.id
        origin_id                = join("-", compact([custom_error_response.error_code, local.s3_origin_id]))
        origin_path              = "${local.root_zones.path != null ? "/${local.root_zones.path}" : ""}/${custom_error_response.response_page.folder_path}"
        origin_headers           = null
        custom_origin_config     = null
        connection_attempts      = null
        connection_timeout       = null
      }
    ],
    flatten([
      for zone in local.zones : concat([{
        domain_name              = zone.origins["static_assets"].domain_name
        origin_access_control_id = aws_cloudfront_origin_access_control.website_origin_access_control.id
        origin_id                = join("-", compact([zone.name, local.s3_origin_id]))
        origin_path              = zone.origins["static_assets"].path
        origin_headers           = null
        custom_origin_config     = null
        connection_attempts      = null
        connection_timeout       = null
        }],
        [for name, origin in zone.origins : {
          domain_name              = origin.domain_name
          origin_access_control_id = origin.auth == "OAC" ? one(aws_cloudfront_origin_access_control.lambda_url_origin_access_control[*].id) : null
          origin_id                = join("-", compact([zone.name, name == "server" ? local.server_function_origin : "${name}-function"]))
          origin_path              = origin.path
          origin_headers           = origin.headers
          custom_origin_config = {
            http_port                = 80
            https_port               = 443
            origin_protocol_policy   = "https-only"
            origin_ssl_protocols     = ["TLSv1.2"]
            origin_keepalive_timeout = origin.keepalive_timeout
            origin_read_timeout      = origin.read_timeout
          }
          connection_attempts = origin.connection_attempts
          connection_timeout  = origin.connection_timeout
        } if contains(["static_assets", "image_optimisation"], name) == false],
        lookup(zone.origins, "image_optimisation", null) == null ? [] : [{
          domain_name              = zone.origins["image_optimisation"].domain_name
          origin_access_control_id = zone.origins["image_optimisation"].auth == "OAC" ? one(aws_cloudfront_origin_access_control.lambda_url_origin_access_control[*].id) : null
          origin_id                = join("-", compact([zone.name, local.image_optimisation_function_origin]))
          origin_path              = null
          origin_headers           = null
          custom_origin_config = {
            http_port                = 80
            https_port               = 443
            origin_protocol_policy   = "https-only"
            origin_ssl_protocols     = ["TLSv1.2"]
            origin_keepalive_timeout = zone.origins["image_optimisation"].keepalive_timeout
            origin_read_timeout      = zone.origins["image_optimisation"].read_timeout
          }
          connection_attempts = zone.origins["image_optimisation"].connection_attempts
          connection_timeout  = zone.origins["image_optimisation"].connection_timeout
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
        action                       = rule.action
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
        // There was a bug in Terraform v1.6.0 which causes this not to work, please upgrade to at least v1.6.1
        search_string = "Basic ${var.waf.enforce_basic_auth.credentials.mark_as_sensitive == false ? base64encode("${var.waf.enforce_basic_auth.credentials.username}:${var.waf.enforce_basic_auth.credentials.password}") : sensitive(base64encode("${var.waf.enforce_basic_auth.credentials.username}:${var.waf.enforce_basic_auth.credentials.password}"))}"
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

  temp_aliases = var.domain_config != null ? concat(formatlist(join(".", compact([var.domain_config.sub_domain, "%s"])), distinct([for hosted_zone in var.domain_config.hosted_zones : hosted_zone.name]))) : []
  aliases      = try(var.domain_config.include_www, false) == true ? flatten([for alias in local.temp_aliases : [alias, "www.${alias}"]]...) : local.temp_aliases
  temp_route53_entries = try(var.domain_config.create_route53_entries, false) == true ? { for hosted_zone in var.domain_config.hosted_zones : join("-", compact([hosted_zone.name, hosted_zone.id, hosted_zone.private_zone])) => {
    name            = join(".", compact([var.domain_config.sub_domain, hosted_zone.name]))
    zone_id         = coalesce(hosted_zone.id, data.aws_route53_zone.hosted_zone[join("-", compact([hosted_zone.name, hosted_zone.private_zone]))].zone_id)
    allow_overwrite = var.domain_config.route53_record_allow_overwrite
  } } : {}
  route53_entries = try(var.domain_config.include_www, false) == true ? merge([for name, route53_details in local.temp_route53_entries : { "${name}" = route53_details, "www_${name}" = { name = "www.${route53_details.name}", zone_id = route53_details.zone_id, allow_overwrite = route53_details.allow_overwrite } }]...) : local.temp_route53_entries
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
      "Resource" : flatten([
        for zone in local.zones : concat([
          for origin_name, origin in zone.origins : [origin.arn, "${origin.arn}:*"] if origin.auth == "AUTH_LAMBDA" && origin.arn != null
        ])
      ]),
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

  timeouts = var.auth_function.timeouts

  providers = {
    aws.iam = aws.iam
  }
}

resource "aws_cloudfront_function" "x_forwarded_host" {
  name    = "${local.prefix}x-forwarded-host-function${local.suffix}"
  runtime = coalesce(try(var.x_forwarded_host_function.runtime, null), "cloudfront-js-1.0")
  publish = true
  code    = coalesce(try(var.x_forwarded_host_function.code, null), file("${path.module}/code/${local.cloudfront_function_code[var.open_next_version_alias]}"))
}

# CloudFront

resource "aws_cloudfront_origin_access_control" "website_origin_access_control" {
  name                              = local.valid_origin_access_control_name
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_origin_access_control" "lambda_url_origin_access_control" {
  count = local.should_create_lambda_url_oac ? 1 : 0

  name                              = "${local.prefix}lambda-url${local.suffix}"
  origin_access_control_origin_type = "lambda"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_cache_policy" "cache_policy" {
  count = local.create_cache_policy ? 1 : 0
  name  = "${local.prefix}cache-policy${local.suffix}"

  default_ttl = try(var.cache_policy.default_ttl, 0)
  max_ttl     = try(var.cache_policy.max_ttl, 31536000)
  min_ttl     = try(var.cache_policy.min_ttl, 0)

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = try(var.cache_policy.cookie_behavior, "all")
    }

    headers_config {
      header_behavior = try(var.cache_policy.header_behavior, "whitelist")

      headers {
        items = coalesce(try(var.cache_policy.header_items, null), local.cache_keys[var.open_next_version_alias])
      }
    }

    query_strings_config {
      query_string_behavior = try(var.cache_policy.query_string_behavior, "all")
    }

    enable_accept_encoding_brotli = try(var.cache_policy.enable_accept_encoding_brotli, null)
    enable_accept_encoding_gzip   = try(var.cache_policy.enable_accept_encoding_gzip, null)
  }
}

resource "aws_cloudfront_response_headers_policy" "response_headers" {
  count = var.response_headers.deployment == "DETACH" || local.create_response_headers ? 1 : 0
  name  = "${local.prefix}response-headers${local.suffix}"

  dynamic "cors_config" {
    for_each = try(var.response_headers.cors_config, null) != null ? [true] : []

    content {
      access_control_allow_credentials = try(var.response_headers.cors_config.access_control_allow_credentials, null)

      access_control_allow_headers {
        items = try(var.response_headers.cors_config.access_control_allow_headers, [])
      }

      access_control_allow_methods {
        items = try(var.response_headers.cors_config.access_control_allow_methods, [])
      }

      access_control_allow_origins {
        items = try(var.response_headers.cors_config.access_control_allow_origins, [])
      }

      dynamic "access_control_expose_headers" {
        for_each = length(var.response_headers.cors_config.access_control_expose_headers) > 0 ? [true] : []

        content {
          items = var.response_headers.cors_config.access_control_expose_headers
        }
      }

      access_control_max_age_sec = try(var.response_headers.cors_config.access_control_max_age_sec, null)

      origin_override = var.response_headers.cors_config.origin_override
    }
  }

  dynamic "custom_headers_config" {
    for_each = length(var.response_headers.custom_headers_config) > 0 ? [true] : []

    content {
      dynamic "items" {
        for_each = var.response_headers.custom_headers_config

        content {
          header   = items.value.header
          override = items.value.override
          value    = items.value.value
        }
      }
    }
  }

  dynamic "remove_headers_config" {
    for_each = length(var.response_headers.remove_headers) > 0 ? [true] : []

    content {
      dynamic "items" {
        for_each = var.response_headers.remove_headers

        content {
          header = items.value
        }
      }
    }
  }

  dynamic "security_headers_config" {
    for_each = try(var.response_headers.security_headers_config, null) != null ? [true] : []

    content {
      dynamic "content_security_policy" {
        for_each = try(var.response_headers.security_headers_config.content_security_policy, null) != null ? [var.response_headers.security_headers_config.content_security_policy] : []

        content {
          content_security_policy = content_security_policy.value.policy
          override                = content_security_policy.value.override
        }
      }

      dynamic "content_type_options" {
        for_each = try(var.response_headers.security_headers_config.content_type_options, null) != null ? [var.response_headers.security_headers_config.content_type_options] : []

        content {
          override = content_type_options.value.override
        }
      }

      dynamic "frame_options" {
        for_each = try(var.response_headers.security_headers_config.frame_options, null) != null ? [var.response_headers.security_headers_config.frame_options] : []
        content {
          frame_option = frame_options.value.frame_option
          override     = frame_options.value.override
        }
      }

      dynamic "referrer_policy" {
        for_each = try(var.response_headers.security_headers_config.referrer_policy, null) != null ? [var.response_headers.security_headers_config.referrer_policy] : []

        content {
          referrer_policy = referrer_policy.value.policy
          override        = referrer_policy.value.override
        }
      }

      dynamic "strict_transport_security" {
        for_each = try(var.response_headers.security_headers_config.strict_transport_security, null) != null ? [var.response_headers.security_headers_config.strict_transport_security] : []

        content {
          access_control_max_age_sec = strict_transport_security.value.max_age
          include_subdomains         = strict_transport_security.value.include_subdomains
          override                   = strict_transport_security.value.override
          preload                    = strict_transport_security.value.preload
        }
      }

      dynamic "xss_protection" {
        for_each = try(var.response_headers.security_headers_config.xss_protection, null) != null ? [var.response_headers.security_headers_config.xss_protection] : []

        content {
          mode_block = xss_protection.value.mode_block
          override   = xss_protection.value.override
          protection = xss_protection.value.protection
          report_uri = xss_protection.value.report_uri
        }
      }
    }
  }

  dynamic "server_timing_headers_config" {
    for_each = try(var.response_headers.server_timing_headers_config, null) != null ? [var.response_headers.server_timing_headers_config] : []

    content {
      enabled       = server_timing_headers_config.value.enabled
      sampling_rate = server_timing_headers_config.value.sampling_rate
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
      connection_attempts      = origin.value.connection_attempts
      connection_timeout       = origin.value.connection_timeout

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
          http_port                = origin.value.custom_origin_config.http_port
          https_port               = origin.value.custom_origin_config.https_port
          origin_protocol_policy   = origin.value.custom_origin_config.origin_protocol_policy
          origin_ssl_protocols     = origin.value.custom_origin_config.origin_ssl_protocols
          origin_keepalive_timeout = origin.value.custom_origin_config.origin_keepalive_timeout
          origin_read_timeout      = origin.value.custom_origin_config.origin_read_timeout
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
      realtime_log_config_arn  = ordered_cache_behavior.value.realtime_log_config_arn
      origin_request_policy_id = ordered_cache_behavior.value.origin_request_policy_id

      response_headers_policy_id = ordered_cache_behavior.value.response_headers_policy_id

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
      realtime_log_config_arn  = default_cache_behavior.value.realtime_log_config_arn
      origin_request_policy_id = default_cache_behavior.value.origin_request_policy_id

      response_headers_policy_id = default_cache_behavior.value.response_headers_policy_id

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
      response_code         = coalesce(try(custom_error_response.value.response_code, null), custom_error_response.value.error_code)
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
      connection_attempts      = origin.value.connection_attempts
      connection_timeout       = origin.value.connection_timeout

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
          http_port                = origin.value.custom_origin_config.http_port
          https_port               = origin.value.custom_origin_config.https_port
          origin_protocol_policy   = origin.value.custom_origin_config.origin_protocol_policy
          origin_ssl_protocols     = origin.value.custom_origin_config.origin_ssl_protocols
          origin_keepalive_timeout = origin.value.custom_origin_config.origin_keepalive_timeout
          origin_read_timeout      = origin.value.custom_origin_config.origin_read_timeout
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
      realtime_log_config_arn  = ordered_cache_behavior.value.realtime_log_config_arn
      origin_request_policy_id = ordered_cache_behavior.value.origin_request_policy_id

      response_headers_policy_id = ordered_cache_behavior.value.response_headers_policy_id

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
      realtime_log_config_arn  = default_cache_behavior.value.realtime_log_config_arn
      origin_request_policy_id = default_cache_behavior.value.origin_request_policy_id

      response_headers_policy_id = default_cache_behavior.value.response_headers_policy_id

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
      response_code         = coalesce(try(custom_error_response.value.response_code, null), custom_error_response.value.error_code)
      response_page_path    = try(custom_error_response.value.response_page, null) != null ? "/${custom_error_response.value.response_page.folder_path}/${custom_error_response.value.response_page.name}" : null
    }
  }

  aliases = local.aliases

  lifecycle {
    ignore_changes = [origin, ordered_cache_behavior, default_cache_behavior, custom_error_response]
  }
}

resource "aws_cloudfront_distribution" "staging_distribution" {
  count = local.includes_staging_distribution ? 1 : 0

  dynamic "origin" {
    for_each = local.origins

    content {
      domain_name              = origin.value.domain_name
      origin_access_control_id = origin.value.origin_access_control_id
      origin_id                = origin.value.origin_id
      origin_path              = origin.value.origin_path
      connection_attempts      = origin.value.connection_attempts
      connection_timeout       = origin.value.connection_timeout

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
          http_port                = origin.value.custom_origin_config.http_port
          https_port               = origin.value.custom_origin_config.https_port
          origin_protocol_policy   = origin.value.custom_origin_config.origin_protocol_policy
          origin_ssl_protocols     = origin.value.custom_origin_config.origin_ssl_protocols
          origin_keepalive_timeout = origin.value.custom_origin_config.origin_keepalive_timeout
          origin_read_timeout      = origin.value.custom_origin_config.origin_read_timeout
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
      realtime_log_config_arn  = ordered_cache_behavior.value.realtime_log_config_arn
      origin_request_policy_id = ordered_cache_behavior.value.origin_request_policy_id

      response_headers_policy_id = ordered_cache_behavior.value.response_headers_policy_id

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
      realtime_log_config_arn  = default_cache_behavior.value.realtime_log_config_arn
      origin_request_policy_id = default_cache_behavior.value.origin_request_policy_id

      response_headers_policy_id = default_cache_behavior.value.response_headers_policy_id

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
      response_code         = coalesce(try(custom_error_response.value.response_code, null), custom_error_response.value.error_code)
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
    command = "${coalesce(try(var.scripts.invalidate_cloudfront_script.interpreter, var.scripts.interpreter, null), "/bin/bash")} ${try(var.scripts.invalidate_cloudfront_script.path, "${path.module}/scripts/invalidate-cloudfront.sh")}"

    environment = merge({
      "CDN_ID" = var.continuous_deployment.use ? one(aws_cloudfront_distribution.production_distribution[*].id) : one(aws_cloudfront_distribution.website_distribution[*].id)
    }, try(var.scripts.additional_environment_variables, {}), try(var.scripts.invalidate_cloudfront_script.additional_environment_variables, {}))
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
    command = "${coalesce(try(var.scripts.invalidate_cloudfront_script.interpreter, var.scripts.interpreter, null), "/bin/bash")} ${try(var.scripts.invalidate_cloudfront_script.path, "${path.module}/scripts/invalidate-cloudfront.sh")}"

    environment = merge({
      "CDN_ID" = one(aws_cloudfront_distribution.staging_distribution[*].id)
    }, try(var.scripts.additional_environment_variables, {}), try(var.scripts.invalidate_cloudfront_script.additional_environment_variables, {}))
  }
}

resource "terraform_data" "promote_distribution" {
  count = var.continuous_deployment.use && var.continuous_deployment.deployment == "PROMOTE" ? 1 : 0

  provisioner "local-exec" {
    command = "${coalesce(try(var.scripts.promote_distribution_script.interpreter, var.scripts.interpreter, null), "/bin/bash")} ${try(var.scripts.promote_distribution_script.path, "${path.module}/scripts/promote-distribution.sh")}"

    environment = merge({
      "CDN_PRODUCTION_ID"   = one(aws_cloudfront_distribution.production_distribution[*].id)
      "CDN_PRODUCTION_ETAG" = one(aws_cloudfront_distribution.production_distribution[*].etag)
      "CDN_STAGING_ID"      = one(aws_cloudfront_distribution.staging_distribution[*].id)
      "CDN_STAGING_ETAG"    = one(aws_cloudfront_distribution.staging_distribution[*].etag)
    }, try(var.scripts.additional_environment_variables, {}), try(var.scripts.promote_distribution_script.additional_environment_variables, {}))
  }
}

# This is a workaround for a bug in the v5 of the AWS terraform provider. More info can be found at https://github.com/hashicorp/terraform-provider-aws/issues/34511
resource "terraform_data" "remove_continuous_deployment_id" {
  count = var.continuous_deployment.use && var.continuous_deployment.deployment == "DETACH" ? 1 : 0

  provisioner "local-exec" {
    command = "${coalesce(try(var.scripts.remove_continuous_deployment_policy_id_script.interpreter, var.scripts.interpreter, null), "/bin/bash")} ${try(var.scripts.remove_continuous_deployment_policy_id_script.path, "${path.module}/scripts/remove-continuous-deployment-policy-id.sh")}"

    environment = merge({
      "CDN_PRODUCTION_ID" = one(aws_cloudfront_distribution.production_distribution[*].id)
    }, try(var.scripts.additional_environment_variables, {}), try(var.scripts.remove_continuous_deployment_policy_id_script.additional_environment_variables, {}))
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

  allow_overwrite = each.value.allow_overwrite
  zone_id         = each.value.zone_id
  name            = each.value.name
  type            = "A"

  alias {
    name                   = var.continuous_deployment.use ? one(aws_cloudfront_distribution.production_distribution[*].domain_name) : one(aws_cloudfront_distribution.website_distribution[*].domain_name)
    zone_id                = var.continuous_deployment.use ? one(aws_cloudfront_distribution.production_distribution[*].hosted_zone_id) : one(aws_cloudfront_distribution.website_distribution[*].hosted_zone_id)
    evaluate_target_health = var.domain_config.evaluate_target_health
  }

  provider = aws.dns
}

resource "aws_route53_record" "route53_aaaa_record" {
  for_each = var.ipv6_enabled == true ? local.route53_entries : {}

  allow_overwrite = each.value.allow_overwrite
  zone_id         = each.value.zone_id
  name            = each.value.name
  type            = "AAAA"

  alias {
    name                   = var.continuous_deployment.use ? one(aws_cloudfront_distribution.production_distribution[*].domain_name) : one(aws_cloudfront_distribution.website_distribution[*].domain_name)
    zone_id                = var.continuous_deployment.use ? one(aws_cloudfront_distribution.production_distribution[*].hosted_zone_id) : one(aws_cloudfront_distribution.website_distribution[*].hosted_zone_id)
    evaluate_target_health = var.domain_config.evaluate_target_health
  }

  provider = aws.dns
}
