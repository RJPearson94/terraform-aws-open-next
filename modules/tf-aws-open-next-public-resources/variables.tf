variable "prefix" {
  description = "A prefix which will be attached to the resource name to ensure resources are random"
  type        = string
  default     = null
}

variable "suffix" {
  description = "A suffix which will be attached to the resource name to ensure resources are random"
  type        = string
  default     = null
}

variable "open_next_version_alias" {
  description = "An alias for the open next version"
  type        = string

  validation {
    condition     = contains(["v2", "v3"], var.open_next_version_alias)
    error_message = "The open next alias can either be v2 or v3"
  }
}

variable "enabled" {
  description = "Whether the CloudFront distrubtion is enabled"
  type        = bool
  default     = true
}

variable "ipv6_enabled" {
  description = "Whether IPV6 is enabled on the distribution"
  type        = bool
  default     = true
}

variable "http_version" {
  description = "The HTTP versions supported by the distribution"
  type        = string
  default     = "http2"
}

variable "price_class" {
  description = "The price class for the distribution"
  type        = string
  default     = "PriceClass_100"
}

variable "geo_restrictions" {
  description = "The geo restrictions for the distribution"
  type = object({
    type      = optional(string, "none"),
    locations = optional(list(string), [])
  })
  default = {}
}

variable "x_forwarded_host_function" {
  description = "The code and configuration to run as part of the x forwarded host cloudfront function. If no value is supplied, then the /code/xForwardedHost.js file will be used and the cloudfront-js-1.0 runtime will be used"
  type = object({
    runtime = optional(string)
    code    = optional(string)
  })
  default = {}
}

variable "auth_function" {
  description = "Configuration for the auth lambda@edge function"
  type = object({
    deployment    = optional(string, "NONE")
    qualified_arn = optional(string)
    function_code = optional(object({
      handler = optional(string, "index.handler")
      zip = optional(object({
        path = string
        hash = string
      }))
      s3 = optional(object({
        bucket         = string
        key            = string
        object_version = optional(string)
      }))
    }))
    runtime     = optional(string, "nodejs20.x")
    timeout     = optional(number, 10)
    memory_size = optional(number, 256)
    additional_iam_policies = optional(list(object({
      name   = string,
      arn    = optional(string)
      policy = optional(string)
    })), [])
    iam = optional(object({
      path                 = optional(string)
      permissions_boundary = optional(string)
    }))
    timeouts = optional(object({
      create = optional(string)
      update = optional(string)
      delete = optional(string)
    }), {})
  })
  default = {}

  validation {
    condition     = contains(["NONE", "USE_EXISTING", "CREATE", "DETACH"], var.auth_function.deployment)
    error_message = "The auth function deployment can be one of NONE, USE_EXISTING, CREATE or DETACH"
  }

  validation {
    condition     = anytrue([contains(["NONE", "CREATE", "DETACH"], var.auth_function.deployment), (var.auth_function.deployment == "USE_EXISTING" && var.auth_function.qualified_arn != null)])
    error_message = "The auth function qualified ARN must be set when the deployment is set to USE_EXISTING"
  }
}

variable "lambda_url_oac" {
  description = "Configuration for the OAC lambda url"
  type = object({
    deployment = optional(string, "NONE")
  })
  default = {}

  validation {
    condition     = contains(["NONE", "CREATE"], var.lambda_url_oac.deployment)
    error_message = "The lambda URL OAC deployment can be one of NONE or CREATE"
  }
}

variable "cache_policy" {
  description = "Configuration for the CloudFront cache policy"
  type = object({
    deployment                    = optional(string, "CREATE")
    id                            = optional(string)
    default_ttl                   = optional(number, 0)
    max_ttl                       = optional(number, 31536000)
    min_ttl                       = optional(number, 0)
    cookie_behavior               = optional(string, "all")
    header_behavior               = optional(string, "whitelist")
    header_items                  = optional(list(string))
    query_string_behavior         = optional(string, "all")
    enable_accept_encoding_brotli = optional(bool)
    enable_accept_encoding_gzip   = optional(bool)
  })
  default = {}

  validation {
    condition     = contains(["USE_EXISTING", "CREATE"], var.cache_policy.deployment)
    error_message = "The cache policy deployment can be one of USE_EXISTING or CREATE"
  }

  validation {
    condition     = anytrue([var.cache_policy.deployment == "CREATE", (var.cache_policy.deployment == "USE_EXISTING" && var.cache_policy.id != null)])
    error_message = "The cache policy ID or ARN must be set when the deployment is set to USE_EXISTING"
  }
}

variable "response_headers" {
  description = "Configuration for the CloudFront response headers"
  type = object({
    deployment = optional(string, "NONE") # NONE, CREATE, USE_EXISTING or DETACH
    id         = optional(string)
    cors_config = optional(object({
      access_control_allow_credentials = bool
      access_control_allow_headers     = list(string)
      access_control_allow_methods     = list(string)
      access_control_allow_origins     = list(string)
      access_control_expose_headers    = optional(list(string), [])
      access_control_max_age_seconds   = optional(number)
      origin_override                  = bool
    }))
    custom_headers_config = optional(list(object({
      header   = string
      override = bool
      value    = string
    })), [])
    remove_headers = optional(list(string), [])
    security_headers_config = optional(object({
      content_security_policy = optional(object({
        policy   = string
        override = bool
      }))
      content_type_options = optional(object({
        override = bool
      }))
      frame_options = optional(object({
        frame_option = string
        override     = bool
      }))
      referrer_policy = optional(object({
        override = bool
        policy   = string
      }))
      strict_transport_security = optional(object({
        max_age            = number
        include_subdomains = optional(bool)
        override           = bool
        preload            = optional(bool)
      }))
      xss_protection = optional(object({
        mode_block = optional(bool)
        override   = bool
        protection = bool
        report_url = optional(string)
      }))
    }))
    server_timing_headers_config = optional(object({
      enabled       = bool
      sampling_rate = number
    }))
  })
  default = {}

  validation {
    condition     = contains(["NONE", "USE_EXISTING", "CREATE", "DETACH"], var.response_headers.deployment)
    error_message = "The response headers deployment can be one of NONE, USE_EXISTING, CREATE, or DETACH"
  }

  validation {
    condition     = anytrue([contains(["NONE", "CREATE", "DETACH"], var.response_headers.deployment), (var.response_headers.deployment == "USE_EXISTING" && var.response_headers.id != null)])
    error_message = "The response headers ID must be set when the deployment is set to USE_EXISTING"
  }

  validation {
    condition     = anytrue([contains(["NONE", "USE_EXISTING", "DETACH"], var.response_headers.deployment), var.response_headers.deployment == "CREATE" && (var.response_headers.id == null || var.response_headers.id == "")])
    error_message = "The response headers ID must be null or empty when the deployment is set to CREATE"
  }
}

variable "zones" {
  description = "Configuration for the website zones to assoicate with the distribution"
  type = list(object({
    root                = bool
    name                = string
    reinvalidation_hash = string
    origins = map(object({
      domain_name         = string
      path                = optional(string)
      arn                 = optional(string)
      auth                = optional(string)
      headers             = optional(map(string))
      keepalive_timeout   = optional(number)
      read_timeout        = optional(number)
      connection_attempts = optional(number)
      connection_timeout  = optional(number)
    }))
    path = optional(string)
  }))

  validation {
    condition     = length(var.zones) > 0
    error_message = "At least 1 zone needs to be supplied"
  }

  validation {
    condition     = length([for zone in var.zones : zone if zone.root == true]) == 1
    error_message = "There must be exactly 1 root zone"
  }

  validation {
    condition = alltrue(flatten([
      for zone in var.zones : [
        for origin in zone.origins : contains(["OAC", "AUTH_LAMBDA"], origin.auth) if origin.auth != null
      ]
    ]))
    error_message = "All origin auth should be either null, OAC or AUTH_LAMBDA"
  }
}

variable "behaviours" {
  description = "Override the default behaviour config"
  type = object({
    custom_error_responses = optional(object({
      path_overrides = optional(map(object({
        allowed_methods            = optional(list(string))
        cached_methods             = optional(list(string))
        cache_policy_id            = optional(string)
        origin_request_policy_id   = optional(string)
        response_headers_policy_id = optional(string)
        compress                   = optional(bool)
        viewer_protocol_policy     = optional(string)
        viewer_request = optional(object({
          type         = string
          arn          = string
          include_body = optional(bool)
        }))
        viewer_response = optional(object({
          type = string
          arn  = string
        }))
        origin_request = optional(object({
          arn          = string
          include_body = bool
        }))
        origin_response = optional(object({
          arn = string
        }))
      })))
      allowed_methods            = optional(list(string))
      cached_methods             = optional(list(string))
      cache_policy_id            = optional(string)
      origin_request_policy_id   = optional(string)
      response_headers_policy_id = optional(string)
      compress                   = optional(bool)
      viewer_protocol_policy     = optional(string)
      viewer_request = optional(object({
        type         = string
        arn          = string
        include_body = optional(bool)
      }))
      viewer_response = optional(object({
        type = string
        arn  = string
      }))
      origin_request = optional(object({
        arn          = string
        include_body = optional(bool)
      }))
      origin_response = optional(object({
        type = string
        arn  = string
      }))
    }))
    static_assets = optional(object({
      zone_overrides = optional(map(object({
        paths            = optional(list(string))
        additional_paths = optional(list(string))
        path_overrides = optional(map(object({
          allowed_methods            = optional(list(string))
          cached_methods             = optional(list(string))
          cache_policy_id            = optional(string)
          origin_request_policy_id   = optional(string)
          response_headers_policy_id = optional(string)
          compress                   = optional(bool)
          viewer_protocol_policy     = optional(string)
          viewer_request = optional(object({
            type         = string
            arn          = string
            include_body = optional(bool)
          }))
          viewer_response = optional(object({
            type = string
            arn  = string
          }))
          origin_request = optional(object({
            arn          = string
            include_body = bool
          }))
          origin_response = optional(object({
            arn = string
          }))
        })))
        allowed_methods            = optional(list(string))
        cached_methods             = optional(list(string))
        cache_policy_id            = optional(string)
        origin_request_policy_id   = optional(string)
        response_headers_policy_id = optional(string)
        compress                   = optional(bool)
        viewer_protocol_policy     = optional(string)
        viewer_request = optional(object({
          type         = string
          arn          = string
          include_body = optional(bool)
        }))
        viewer_response = optional(object({
          type = string
          arn  = string
        }))
        origin_request = optional(object({
          arn          = string
          include_body = optional(bool)
        }))
        origin_response = optional(object({
          type = string
          arn  = string
        }))
      })))
      paths            = optional(list(string))
      additional_paths = optional(list(string))
      path_overrides = optional(map(object({
        allowed_methods            = optional(list(string))
        cached_methods             = optional(list(string))
        cache_policy_id            = optional(string)
        origin_request_policy_id   = optional(string)
        response_headers_policy_id = optional(string)
        compress                   = optional(bool)
        viewer_protocol_policy     = optional(string)
        viewer_request = optional(object({
          type         = string
          arn          = string
          include_body = optional(bool)
        }))
        viewer_response = optional(object({
          type = string
          arn  = string
        }))
        origin_request = optional(object({
          arn          = string
          include_body = bool
        }))
        origin_response = optional(object({
          arn = string
        }))
      })))
      allowed_methods            = optional(list(string))
      cached_methods             = optional(list(string))
      cache_policy_id            = optional(string)
      origin_request_policy_id   = optional(string)
      response_headers_policy_id = optional(string)
      compress                   = optional(bool)
      viewer_protocol_policy     = optional(string)
      viewer_request = optional(object({
        type         = string
        arn          = string
        include_body = optional(bool)
      }))
      viewer_response = optional(object({
        type = string
        arn  = string
      }))
      origin_request = optional(object({
        arn          = string
        include_body = optional(bool)
      }))
      origin_response = optional(object({
        type = string
        arn  = string
      }))
    }))
    server = optional(object({
      zone_overrides = optional(map(object({
        paths = optional(list(string))
        path_overrides = optional(map(object({
          allowed_methods            = optional(list(string))
          cached_methods             = optional(list(string))
          cache_policy_id            = optional(string)
          origin_request_policy_id   = optional(string)
          response_headers_policy_id = optional(string)
          compress                   = optional(bool)
          viewer_protocol_policy     = optional(string)
          viewer_request = optional(object({
            type         = string
            arn          = string
            include_body = optional(bool)
          }))
          viewer_response = optional(object({
            type = string
            arn  = string
          }))
          origin_request = optional(object({
            arn          = string
            include_body = bool
          }))
          origin_response = optional(object({
            arn = string
          }))
        })))
        allowed_methods            = optional(list(string))
        cached_methods             = optional(list(string))
        cache_policy_id            = optional(string)
        origin_request_policy_id   = optional(string)
        response_headers_policy_id = optional(string)
        compress                   = optional(bool)
        viewer_protocol_policy     = optional(string)
        viewer_request = optional(object({
          type         = string
          arn          = string
          include_body = optional(bool)
        }))
        viewer_response = optional(object({
          type = string
          arn  = string
        }))
        origin_request = optional(object({
          arn          = string
          include_body = optional(bool)
        }))
        origin_response = optional(object({
          type = string
          arn  = string
        }))
      })))
      paths = optional(list(string))
      path_overrides = optional(map(object({
        allowed_methods            = optional(list(string))
        cached_methods             = optional(list(string))
        cache_policy_id            = optional(string)
        origin_request_policy_id   = optional(string)
        response_headers_policy_id = optional(string)
        compress                   = optional(bool)
        viewer_protocol_policy     = optional(string)
        viewer_request = optional(object({
          type         = string
          arn          = string
          include_body = optional(bool)
        }))
        viewer_response = optional(object({
          type = string
          arn  = string
        }))
        origin_request = optional(object({
          arn          = string
          include_body = bool
        }))
        origin_response = optional(object({
          arn = string
        }))
      })))
      allowed_methods            = optional(list(string))
      cached_methods             = optional(list(string))
      cache_policy_id            = optional(string)
      origin_request_policy_id   = optional(string)
      response_headers_policy_id = optional(string)
      compress                   = optional(bool)
      viewer_protocol_policy     = optional(string)
      viewer_request = optional(object({
        type         = string
        arn          = string
        include_body = optional(bool)
      }))
      viewer_response = optional(object({
        type = string
        arn  = string
      }))
      origin_request = optional(object({
        arn          = string
        include_body = optional(bool)
      }))
      origin_response = optional(object({
        type = string
        arn  = string
      }))
    }))
    additional_origins = optional(map(object({
      paths = optional(list(string))
      path_overrides = optional(map(object({
        allowed_methods            = optional(list(string))
        cached_methods             = optional(list(string))
        cache_policy_id            = optional(string)
        origin_request_policy_id   = optional(string)
        response_headers_policy_id = optional(string)
        compress                   = optional(bool)
        viewer_protocol_policy     = optional(string)
        viewer_request = optional(object({
          type         = string
          arn          = string
          include_body = optional(bool)
        }))
        viewer_response = optional(object({
          type = string
          arn  = string
        }))
        origin_request = optional(object({
          arn          = string
          include_body = bool
        }))
        origin_response = optional(object({
          arn = string
        }))
      })))
      allowed_methods            = optional(list(string))
      cached_methods             = optional(list(string))
      cache_policy_id            = optional(string)
      origin_request_policy_id   = optional(string)
      response_headers_policy_id = optional(string)
      compress                   = optional(bool)
      viewer_protocol_policy     = optional(string)
      viewer_request = optional(object({
        type         = string
        arn          = string
        include_body = optional(bool)
      }))
      viewer_response = optional(object({
        type = string
        arn  = string
      }))
      origin_request = optional(object({
        arn          = string
        include_body = optional(bool)
      }))
      origin_response = optional(object({
        type = string
        arn  = string
      }))
    })))
    image_optimisation = optional(object({
      zone_overrides = optional(map(object({
        paths = optional(list(string))
        path_overrides = optional(map(object({
          allowed_methods            = optional(list(string))
          cached_methods             = optional(list(string))
          cache_policy_id            = optional(string)
          origin_request_policy_id   = optional(string)
          response_headers_policy_id = optional(string)
          compress                   = optional(bool)
          viewer_protocol_policy     = optional(string)
          viewer_request = optional(object({
            type         = string
            arn          = string
            include_body = optional(bool)
          }))
          viewer_response = optional(object({
            type = string
            arn  = string
          }))
          origin_request = optional(object({
            arn          = string
            include_body = bool
          }))
          origin_response = optional(object({
            arn = string
          }))
        })))
        allowed_methods            = optional(list(string))
        cached_methods             = optional(list(string))
        cache_policy_id            = optional(string)
        origin_request_policy_id   = optional(string)
        response_headers_policy_id = optional(string)
        compress                   = optional(bool)
        viewer_protocol_policy     = optional(string)
        viewer_request = optional(object({
          type         = string
          arn          = string
          include_body = optional(bool)
        }))
        viewer_response = optional(object({
          type = string
          arn  = string
        }))
        origin_request = optional(object({
          arn          = string
          include_body = optional(bool)
        }))
        origin_response = optional(object({
          type = string
          arn  = string
        }))
      })))
      paths = optional(list(string))
      path_overrides = optional(map(object({
        allowed_methods            = optional(list(string))
        cached_methods             = optional(list(string))
        cache_policy_id            = optional(string)
        origin_request_policy_id   = optional(string)
        response_headers_policy_id = optional(string)
        compress                   = optional(bool)
        viewer_protocol_policy     = optional(string)
        viewer_request = optional(object({
          type         = string
          arn          = string
          include_body = optional(bool)
        }))
        viewer_response = optional(object({
          type = string
          arn  = string
        }))
        origin_request = optional(object({
          arn          = string
          include_body = bool
        }))
        origin_response = optional(object({
          arn = string
        }))
      })))
      allowed_methods            = optional(list(string))
      cached_methods             = optional(list(string))
      cache_policy_id            = optional(string)
      origin_request_policy_id   = optional(string)
      response_headers_policy_id = optional(string)
      compress                   = optional(bool)
      viewer_protocol_policy     = optional(string)
      viewer_request = optional(object({
        type         = string
        arn          = string
        include_body = optional(bool)
      }))
      viewer_response = optional(object({
        type = string
        arn  = string
      }))
      origin_request = optional(object({
        arn          = string
        include_body = optional(bool)
      }))
      origin_response = optional(object({
        type = string
        arn  = string
      }))
    }))
  })
  default = {}
}

variable "waf" {
  description = "Configuration for the CloudFront distribution WAF. For enforce basic auth, to protect the secret value, the encoded string has been marked as sensitive. I would make this configurable to allow it to be marked as sensitive or not however Terraform panics when you use the sensitive function as part of a ternary. If you need to see all rules, see this discussion https://discuss.hashicorp.com/t/how-to-show-sensitive-values/24076/4"
  type = object({
    deployment = optional(string, "NONE")
    web_acl_id = optional(string)
    aws_managed_rules = optional(list(object({
      priority              = optional(number)
      name                  = string
      aws_managed_rule_name = string
      })), [{
      name                  = "amazon-ip-reputation-list"
      aws_managed_rule_name = "AWSManagedRulesAmazonIpReputationList"
      }, {
      name                  = "common-rule-set"
      aws_managed_rule_name = "AWSManagedRulesCommonRuleSet"
      }, {
      name                  = "known-bad-inputs"
      aws_managed_rule_name = "AWSManagedRulesKnownBadInputsRuleSet"
    }])
    rate_limiting = optional(object({
      enabled = optional(bool, false)
      limits = optional(list(object({
        priority         = optional(number)
        rule_name_suffix = optional(string)
        limit            = optional(number, 1000)
        action           = optional(string, "BLOCK")
        geo_match_scope  = optional(list(string))
      })), [])
    }), {})
    sqli = optional(object({
      enabled  = optional(bool, false)
      priority = optional(number)
    }), {})
    account_takeover_protection = optional(object({
      enabled              = optional(bool, false)
      priority             = optional(number)
      login_path           = string
      enable_regex_in_path = optional(bool)
      request_inspection = optional(object({
        username_field_identifier = string
        password_field_identifier = string
        payload_type              = string
      }))
      response_inspection = optional(object({
        failure_codes = list(string)
        success_codes = list(string)
      }))
    }))
    account_creation_fraud_prevention = optional(object({
      enabled                = optional(bool, false)
      priority               = optional(number)
      creation_path          = string
      registration_page_path = string
      enable_regex_in_path   = optional(bool)
      request_inspection = optional(object({
        email_field_identifier    = string
        username_field_identifier = string
        password_field_identifier = string
        payload_type              = string
      }))
      response_inspection = optional(object({
        failure_codes = list(string)
        success_codes = list(string)
      }))
    }))
    enforce_basic_auth = optional(object({
      enabled       = optional(bool, false)
      priority      = optional(number)
      response_code = optional(number, 401)
      response_header = optional(object({
        name  = optional(string, "WWW-Authenticate")
        value = optional(string, "Basic realm=\"Requires basic auth\"")
      }), {})
      header_name = optional(string, "authorization")
      credentials = optional(object({
        username          = string
        password          = string
        mark_as_sensitive = optional(bool, true)
      }))
      ip_address_restrictions = optional(list(object({
        action = optional(string, "BYPASS")
        arn    = optional(string)
        name   = optional(string)
      })))
    }))
    additional_rules = optional(list(object({
      enabled  = optional(bool, false)
      priority = optional(number)
      name     = string
      action   = optional(string, "COUNT")
      block_action = optional(object({
        response_code = number
        response_header = optional(object({
          name  = string
          value = string
        }))
        custom_response_body_key = optional(string)
      }))
      ip_address_restrictions = list(object({
        action = optional(string, "BYPASS")
        arn    = optional(string)
        name   = optional(string)
      }))
    })))
    default_action = optional(object({
      action = optional(string, "ALLOW")
      block_action = optional(object({
        response_code = number
        response_header = optional(object({
          name  = string
          value = string
        }))
        custom_response_body_key = optional(string)
      }))
    }))
    ip_addresses = optional(map(object({
      description        = optional(string)
      ip_address_version = string
      addresses          = list(string)
    })))
    custom_response_bodies = optional(list(object({
      key          = string
      content      = string
      content_type = string
    })))
  })
  default = {}

  validation {
    condition     = contains(["NONE", "USE_EXISTING", "CREATE", "DETACH"], var.waf.deployment)
    error_message = "The WAF deployment can be one of NONE, USE_EXISTING, CREATE or DETACH"
  }

  validation {
    condition     = anytrue([contains(["NONE", "CREATE", "DETACH"], var.waf.deployment), (var.waf.deployment == "USE_EXISTING" && var.waf.web_acl_id != null)])
    error_message = "The Web ACL ID must be set when the deployment is set to USE_EXISTING"
  }

  validation {
    condition     = var.waf.default_action == null ? true : contains(["ALLOW", "BLOCK"], var.waf.default_action.action)
    error_message = "The WAF default action can be one of ALLOW or BLOCK"
  }

  validation {
    condition = var.waf.additional_rules == null ? true : alltrue([
      for additional_rule in var.waf.additional_rules : contains(["COUNT", "BLOCK"], additional_rule.action)
    ])
    error_message = "All additional rule actions must be either COUNT or BLOCK"
  }

  validation {
    condition = var.waf.additional_rules == null ? true : alltrue(flatten([
      for additional_rule in var.waf.additional_rules : [
        for ip_address_restriction in additional_rule.ip_address_restrictions : contains(["BYPASS", "BLOCK"], ip_address_restriction.action)
      ]
    ]))
    error_message = "All IP address restriction actions must be either BYPASS or BLOCK for each additional rule"
  }

  validation {
    condition = try(var.waf.enforce_basic_auth.ip_address_restrictions, null) == null ? true : alltrue([
      for ip_address_restriction in var.waf.enforce_basic_auth.ip_address_restrictions : contains(["BYPASS", "BLOCK"], ip_address_restriction.action)
    ])
    error_message = "All IP address restriction actions must be either BYPASS or BLOCK for basic auth"
  }

  validation {
    condition = try(var.waf.rate_limiting.limits, null) == null ? true : alltrue([
      for limit in var.waf.rate_limiting.limits : contains(["COUNT", "BLOCK"], limit.action)
    ])
    error_message = "All rate limit actions must be either COUNT or BLOCK"
  }
}

variable "domain_config" {
  description = "Configuration for CloudFront distribution domain"
  type = object({
    evaluate_target_health = optional(bool, true)
    include_www            = optional(bool, false)
    sub_domain             = optional(string)
    hosted_zones = list(object({
      name         = string
      id           = optional(string)
      private_zone = optional(bool, false)
    }))
    create_route53_entries         = optional(bool, true)
    route53_record_allow_overwrite = optional(bool, true)
    viewer_certificate = optional(object({
      acm_certificate_arn      = string
      ssl_support_method       = optional(string, "sni-only")
      minimum_protocol_version = optional(string, "TLSv1.2_2021")
    }))
  })
  default = null
}

variable "continuous_deployment" {
  description = "Configuration for continuous deployment config for CloudFront"
  type = object({
    use        = optional(bool)
    deployment = optional(string)
    traffic_config = optional(object({
      header = optional(object({
        name  = string
        value = string
      }))
      weight = optional(object({
        percentage = number
        session_stickiness = optional(object({
          idle_ttl    = number
          maximum_ttl = number
        }))
      }))
    }))
  })

  validation {
    condition     = anytrue([var.continuous_deployment.use == false, (var.continuous_deployment.use == true && var.continuous_deployment.deployment != null)])
    error_message = "Deployment must be set when continuous deployment is used"
  }

  validation {
    condition     = (var.continuous_deployment.use == false || var.continuous_deployment.deployment == null) ? true : contains(["NONE", "ACTIVE", "DETACH", "PROMOTE"], var.continuous_deployment.deployment)
    error_message = "The deployment strategy can be one of NONE, ACTIVE, DETACH or PROMOTE"
  }

  validation {
    condition     = anytrue([var.continuous_deployment.use == false || var.continuous_deployment.deployment == null ? true : contains(["NONE", "DETACH", "PROMOTE"], var.continuous_deployment.deployment)]) ? true : (var.continuous_deployment.deployment == "ACTIVE" && var.continuous_deployment.traffic_config != null)
    error_message = "The traffic config must be set when the deployment is set to active"
  }

  validation {
    condition     = anytrue([var.continuous_deployment.use == false, var.continuous_deployment.deployment == null ? true : contains(["NONE", "DETACH", "PROMOTE"], var.continuous_deployment.deployment), var.continuous_deployment.traffic_config == null]) ? true : (var.continuous_deployment.traffic_config.header != null || var.continuous_deployment.traffic_config.weight != null)
    error_message = "Either the header or weight traffic config needs to be set"
  }
}

variable "custom_error_responses" {
  description = "Custom error responses to be set on the CloudFront distribution"
  type = list(object({
    bucket_domain_name    = string
    error_code            = string
    error_caching_min_ttl = optional(number)
    response_code         = optional(string)
    response_page = optional(object({
      name        = string
      behaviour   = string
      folder_path = string
    }))
  }))
  default = []
}

variable "scripts" {
  description = "Modify default script behaviours"
  type = object({
    interpreter                      = optional(string)
    additional_environment_variables = optional(map(string))
    invalidate_cloudfront_script = optional(object({
      interpreter                      = optional(string)
      path                             = optional(string)
      additional_environment_variables = optional(map(string))
    }))
    promote_distribution_script = optional(object({
      interpreter                      = optional(string)
      path                             = optional(string)
      additional_environment_variables = optional(map(string))
    }))
    remove_continuous_deployment_policy_id_script = optional(object({
      interpreter                      = optional(string)
      path                             = optional(string)
      additional_environment_variables = optional(map(string))
    }))
  })
  default = {}
}
