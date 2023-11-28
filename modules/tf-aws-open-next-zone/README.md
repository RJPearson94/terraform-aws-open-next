# Open Next Terraform - tf-aws-open-next-zone

This module allows you to deploy a next.js website using [Open Next](https://github.com/serverless-stack/open-next) to AWS utilizing lambda, S3 and CloudFront. Using this module will enable you to configure a single zone. If you want to manage [multiple zones](https://nextjs.org/docs/pages/building-your-application/deploying/multi-zones), please use the [tf-aws-open-next-multi-zone](../tf-aws-open-next-multi-zone) module instead.

The module will allow you to configure the following resources.

![Single Zone Complete](../../docs/diagrams/Single%20Zone.png)

The following are optional:
- Route 53 (A and AAAA records)
- WAF
- Staging Distribution
- Warmer function
- Image Optimization function
- Tag to Path Mapping DB

See the module documentation section below for more info.

*Note:* This module uses multiple bash scripts to delete data, upload data and mutate resources outside of Terraform. This prevents Terraform from removing resources when they have changed and allows the staging distribution functionality to work correctly. 

If you need to destroy the Terraform resources, it is recommended that you enable `force_destroy` on the website bucket to delete the assets in the bucket when running a Terraform destory.

You must configure the environment to use the same credentials or environment variables as the default AWS provider for this functionality to work correctly.

## Continuous deployment

This module supports CloudFront continuous deployment. For this functionality to work correctly, lifecycle rules have been added to the production distribution to ignore changes to origins, ordered_cache_behaviors and default_cache_behavior. For Terraform to be able to update the distribution, you will need to update the staging distribution and then promote the changes.

### Initial deployment

AWS doesn't allow you to attach the continuous deployment policy to the production distribution on the first deployment. Therefore, you will need to set the deployment to `NONE`. To configure this, please add the following configuration.

```tf
continuous_deployment = {
  use = true
  deployment = "NONE"
}
```

### Use staging distribution

When you want to create/ use the staging distribution, there are two options for shifting traffic to the staging distribution header or by weight (up to 15% at the time of writing). To configure this, please add the following configuration.

```tf
continuous_deployment = {
  use = true
  deployment = "ACTIVE"
  traffic_config = {
    header = {
      name = "aws-cf-cd-staging" # Update the header name with a value of your choice. Currently, AWS enforce the header starts with `aws-cf-cd`
      value = "true" # Update the header value with a value of your choice.
    }
  }
}
```

or 

```tf
continuous_deployment = {
  use = true
  deployment = "ACTIVE"
  traffic_config = {
    weight = {
        percentage = "0.10" 
    }
  }
}
```

For weighted deployments, you can also configure session stickiness. See the documentation below for more information.

*Note:* You can update the staging distribution multiple times before promoting the changes.

### Promotion

Please add the following configuration to promote the staging distribution.

```tf
continuous_deployment = {
  use = true
  deployment = "PROMOTE"
  traffic_config = {
    weight = {
        percentage = "0.10" 
    }
  }
}
```

### Detach staging distribution

You must remove the continuous deployment policy from the production distribution to remove the staging distribution. To do this, you must set the deployment to `DETACH`. Please add the following configuration.

```tf
continuous_deployment = {
  use = true
  deployment = "DETACH"
  traffic_config = {
    weight = {
        percentage = "0.10" 
    }
  }
}
```

*Note:* you can detach the staging distribution without promoting the changes to the production distribution. This will remove the continuous deployment policy, shifting 100% of traffic back to the production distribution.

### Remove staging distribution

Please add the following configuration to remove the staging distribution.

```tf
continuous_deployment = {
  use = true
  deployment = "NONE"
}
```

*Note:* Please detach the staging distribution before removing it, otherwise Terraform may fail if the production distribution is retained.

## Backend Server Deployment Options

Several options exist to deploy the backend. The options are:

### Lambda function URLs (with no auth)

Lambda function URL (with no auth) is supported for both the Server and Image Optimisation functions. This is the default deployment model. To configure this, please add the following configuration.

```tf
...
server_function = {
  deployment = "REGIONAL_LAMBDA"
  ...
}

image_optimisation_function = {
  deployment = "REGIONAL_LAMBDA"
  ...
}
```

*Note:* This will deploy the corresponding function without any auth

### Lambda function URLs with IAM Auth (using lambda@edge auth function)

Some companies do not allow lambda URLs to be configured without auth. Hence, AWS released a [blog post](https://aws.amazon.com/blogs/compute/protecting-an-aws-lambda-function-url-with-amazon-cloudfront-and-lambdaedge/) which demonstrated how you could use an auth function (running as lambda@edge) to generate the SigV4 required to call the sever function with the correct Authorization header. To configure this, please add the following configuration.

```tf
...
server_function = {
  deployment = "REGIONAL_LAMBDA_WITH_AUTH_LAMBDA"
  ...
}

image_optimisation_function = {
  deployment = "REGIONAL_LAMBDA_WITH_AUTH_LAMBDA"
  ...
}
```

Using this deployment model does add additional resources and cost; however, this is a workaround until CloudFront natively supports generating signatures to call a lambda protected by IAM auth.


### Lambda@edge (server function only)

Please add the following configuration if you want to run the server function as a lambda@edge function.

```tf
provider "aws" {
  alias = "server_function"
  region = "us-east-1" # For lambda@edge to be used, the region must be set to us-east-1
}

...
server_function = {
  deployment = "EDGE_LAMBDA"
  ...
}
```

As lambda@edge does not support environment variables, the module will inject them at the top of the server code before it is uploaded to AWS. Credit to SST for the inspiration behind this. [Link]( https://github.com/sst/sst/blob/3b792053d90c49d9ca693308646a3389babe9ceb/packages/sst/src/constructs/EdgeFunction.ts#L193)


## Module documentation

Below is the documentation for the Terraform module, outlining the providers, modules and resources required to deploy the website. The documentation includes the inputs that can be supplied (including any defaults) and what is outputted from the module.

By default, the module will zip all the necessary open-next artefacts as part of a Terraform deployment. To facilitate this, the .open-next folders need to be stored locally. 

You can also choose to upload the artefacts to S3 and pass the reference in. 

*Note:* the logic to automatically inject environment variables for lambda@edge functions will not run if you choose this option

Alternatively you can create the zip using your own tooling and supply the path to the zip file and the hash (SHA256 hash of the file encoded using Base64).

You must configure the AWS providers five times because some organizations use different accounts or roles for IAM, DNS, etc. The module has been designed to cater for these requirements. The server function is a separate provider to allow your backend resources to be deployed to a region, i.e. eu-west-1, and deploy the server function to another region, i.e. us-east-1, for lambda@edge. The `global` provider region should be set to us-east-1 to allow the auth-function, WAF, etc. to be configured correctly.

Below is an example setup.

```tf
provider "aws" {}

provider "aws" {
  alias = "server_function"
}

provider "aws" {
  alias = "iam"
}

provider "aws" {
  alias = "dns"
}

provider "aws" {
  alias  = "global"
  region = "us-east-1"
}
```

### Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.4.0 |
| <a name="requirement_archive"></a> [archive](#requirement\_archive) | >= 2.3.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 4.67.0 |
| <a name="requirement_local"></a> [local](#requirement\_local) | >= 2.4.0 |

### Providers

| Name | Version |
|------|---------|
| <a name="provider_archive"></a> [archive](#provider\_archive) | 2.4.0 |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 5.27.0 |
| <a name="provider_local"></a> [local](#provider\_local) | 2.4.0 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

### Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_image_optimisation_function"></a> [image\_optimisation\_function](#module\_image\_optimisation\_function) | ../tf-aws-lambda | n/a |
| <a name="module_open_next_aliases"></a> [open\_next\_aliases](#module\_open\_next\_aliases) | ../tf-aws-open-next-aliases | n/a |
| <a name="module_public_resources"></a> [public\_resources](#module\_public\_resources) | ../tf-aws-open-next-public-resources | n/a |
| <a name="module_revalidation_function"></a> [revalidation\_function](#module\_revalidation\_function) | ../tf-aws-lambda | n/a |
| <a name="module_s3_assets"></a> [s3\_assets](#module\_s3\_assets) | ../tf-aws-open-next-s3-assets | n/a |
| <a name="module_server_function"></a> [server\_function](#module\_server\_function) | ../tf-aws-lambda | n/a |
| <a name="module_warmer_function"></a> [warmer\_function](#module\_warmer\_function) | ../tf-aws-lambda | n/a |

### Resources

| Name | Type |
|------|------|
| [aws_dynamodb_table.isr_table](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table) | resource |
| [aws_lambda_event_source_mapping.revalidation_queue_source](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_event_source_mapping) | resource |
| [aws_s3_bucket.bucket](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_policy.bucket_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_sqs_queue.revalidation_queue](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue) | resource |
| [local_file.lambda_at_edge_modifications](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| terraform_data.isr_table_item | resource |
| terraform_data.update_aliases | resource |
| [archive_file.image_optimisation_function](https://registry.terraform.io/providers/hashicorp/archive/latest/docs/data-sources/file) | data source |
| [archive_file.revalidation_function](https://registry.terraform.io/providers/hashicorp/archive/latest/docs/data-sources/file) | data source |
| [archive_file.server_function](https://registry.terraform.io/providers/hashicorp/archive/latest/docs/data-sources/file) | data source |
| [archive_file.warmer_function](https://registry.terraform.io/providers/hashicorp/archive/latest/docs/data-sources/file) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

### Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_aliases"></a> [aliases](#input\_aliases) | The production and staging aliases to use | <pre>object({<br>    production = string<br>    staging    = string<br>  })</pre> | `null` | no |
| <a name="input_behaviours"></a> [behaviours](#input\_behaviours) | Override the default behaviour config | <pre>object({<br>    custom_error_pages = optional(object({<br>      path_overrides = optional(map(object({<br>        allowed_methods          = optional(list(string))<br>        cached_methods           = optional(list(string))<br>        cache_policy_id          = optional(string)<br>        origin_request_policy_id = optional(string)<br>        compress                 = optional(bool)<br>        viewer_protocol_policy   = optional(string)<br>        viewer_request = optional(object({<br>          type         = string<br>          arn          = string<br>          include_body = optional(bool)<br>        }))<br>        viewer_response = optional(object({<br>          type = string<br>          arn  = string<br>        }))<br>        origin_request = optional(object({<br>          arn          = string<br>          include_body = bool<br>        }))<br>        origin_response = optional(object({<br>          arn = string<br>        }))<br>      })))<br>      allowed_methods          = optional(list(string))<br>      cached_methods           = optional(list(string))<br>      cache_policy_id          = optional(string)<br>      origin_request_policy_id = optional(string)<br>      compress                 = optional(bool)<br>      viewer_protocol_policy   = optional(string)<br>      viewer_request = optional(object({<br>        type         = string<br>        arn          = string<br>        include_body = optional(bool)<br>      }))<br>      viewer_response = optional(object({<br>        type = string<br>        arn  = string<br>      }))<br>      origin_request = optional(object({<br>        type         = string<br>        arn          = string<br>        include_body = optional(bool)<br>      }))<br>      origin_response = optional(object({<br>        type = string<br>        arn  = string<br>      }))<br>    }))<br>    static_assets = optional(object({<br>      paths            = optional(list(string))<br>      additional_paths = optional(list(string))<br>      path_overrides = optional(map(object({<br>        allowed_methods          = optional(list(string))<br>        cached_methods           = optional(list(string))<br>        cache_policy_id          = optional(string)<br>        origin_request_policy_id = optional(string)<br>        compress                 = optional(bool)<br>        viewer_protocol_policy   = optional(string)<br>        viewer_request = optional(object({<br>          type         = string<br>          arn          = string<br>          include_body = optional(bool)<br>        }))<br>        viewer_response = optional(object({<br>          type = string<br>          arn  = string<br>        }))<br>        origin_request = optional(object({<br>          arn          = string<br>          include_body = bool<br>        }))<br>        origin_response = optional(object({<br>          arn = string<br>        }))<br>      })))<br>      allowed_methods          = optional(list(string))<br>      cached_methods           = optional(list(string))<br>      cache_policy_id          = optional(string)<br>      origin_request_policy_id = optional(string)<br>      compress                 = optional(bool)<br>      viewer_protocol_policy   = optional(string)<br>      viewer_request = optional(object({<br>        type         = string<br>        arn          = string<br>        include_body = optional(bool)<br>      }))<br>      viewer_response = optional(object({<br>        type = string<br>        arn  = string<br>      }))<br>      origin_request = optional(object({<br>        type         = string<br>        arn          = string<br>        include_body = optional(bool)<br>      }))<br>      origin_response = optional(object({<br>        type = string<br>        arn  = string<br>      }))<br>    }))<br>    server = optional(object({<br>      paths = optional(list(string))<br>      path_overrides = optional(map(object({<br>        allowed_methods          = optional(list(string))<br>        cached_methods           = optional(list(string))<br>        cache_policy_id          = optional(string)<br>        origin_request_policy_id = optional(string)<br>        compress                 = optional(bool)<br>        viewer_protocol_policy   = optional(string)<br>        viewer_request = optional(object({<br>          type         = string<br>          arn          = string<br>          include_body = optional(bool)<br>        }))<br>        viewer_response = optional(object({<br>          type = string<br>          arn  = string<br>        }))<br>        origin_request = optional(object({<br>          arn          = string<br>          include_body = bool<br>        }))<br>        origin_response = optional(object({<br>          arn = string<br>        }))<br>      })))<br>      allowed_methods          = optional(list(string))<br>      cached_methods           = optional(list(string))<br>      cache_policy_id          = optional(string)<br>      origin_request_policy_id = optional(string)<br>      compress                 = optional(bool)<br>      viewer_protocol_policy   = optional(string)<br>      viewer_request = optional(object({<br>        type         = string<br>        arn          = string<br>        include_body = optional(bool)<br>      }))<br>      viewer_response = optional(object({<br>        type = string<br>        arn  = string<br>      }))<br>      origin_request = optional(object({<br>        type         = string<br>        arn          = string<br>        include_body = optional(bool)<br>      }))<br>      origin_response = optional(object({<br>        type = string<br>        arn  = string<br>      }))<br>    }))<br>    image_optimisation = optional(object({<br>      paths = optional(list(string))<br>      path_overrides = optional(map(object({<br>        allowed_methods          = optional(list(string))<br>        cached_methods           = optional(list(string))<br>        cache_policy_id          = optional(string)<br>        origin_request_policy_id = optional(string)<br>        compress                 = optional(bool)<br>        viewer_protocol_policy   = optional(string)<br>        viewer_request = optional(object({<br>          type         = string<br>          arn          = string<br>          include_body = optional(bool)<br>        }))<br>        viewer_response = optional(object({<br>          type = string<br>          arn  = string<br>        }))<br>        origin_request = optional(object({<br>          arn          = string<br>          include_body = bool<br>        }))<br>        origin_response = optional(object({<br>          arn = string<br>        }))<br>      })))<br>      allowed_methods          = optional(list(string))<br>      cached_methods           = optional(list(string))<br>      cache_policy_id          = optional(string)<br>      origin_request_policy_id = optional(string)<br>      compress                 = optional(bool)<br>      viewer_protocol_policy   = optional(string)<br>      viewer_request = optional(object({<br>        type         = string<br>        arn          = string<br>        include_body = optional(bool)<br>      }))<br>      viewer_response = optional(object({<br>        type = string<br>        arn  = string<br>      }))<br>      origin_request = optional(object({<br>        type         = string<br>        arn          = string<br>        include_body = optional(bool)<br>      }))<br>      origin_response = optional(object({<br>        type = string<br>        arn  = string<br>      }))<br>    }))<br>  })</pre> | `{}` | no |
| <a name="input_cache_control_immutable_assets_regex"></a> [cache\_control\_immutable\_assets\_regex](#input\_cache\_control\_immutable\_assets\_regex) | Regex to set public,max-age=31536000,immutable on immutable resources | `string` | `"^.*(\\.next)$"` | no |
| <a name="input_cloudwatch_log"></a> [cloudwatch\_log](#input\_cloudwatch\_log) | The default cloudwatch log group. This can be overridden for each function | <pre>object({<br>    retention_in_days = number<br>  })</pre> | <pre>{<br>  "retention_in_days": 7<br>}</pre> | no |
| <a name="input_content_types"></a> [content\_types](#input\_content\_types) | The MIME type mapping and default for artefacts generated by Open Next | <pre>object({<br>    mapping = optional(map(string), {<br>      "svg"  = "image/svg+xml",<br>      "js"   = "application/javascript",<br>      "css"  = "text/css",<br>      "html" = "text/html"<br>    })<br>    default = optional(string, "binary/octet-stream")<br>  })</pre> | `{}` | no |
| <a name="input_continuous_deployment"></a> [continuous\_deployment](#input\_continuous\_deployment) | Configuration for continuous deployment config for CloudFront | <pre>object({<br>    use        = optional(bool, true)<br>    deployment = optional(string, "NONE")<br>    traffic_config = optional(object({<br>      header = optional(object({<br>        name  = string<br>        value = string<br>      }))<br>      weight = optional(object({<br>        percentage = number<br>        session_stickiness = optional(object({<br>          idle_ttl    = number<br>          maximum_ttl = number<br>        }))<br>      }))<br>    }))<br>  })</pre> | `{}` | no |
| <a name="input_custom_error_responses"></a> [custom\_error\_responses](#input\_custom\_error\_responses) | Allow custom error responses to be set on the distributions | <pre>list(object({<br>    error_code            = string<br>    error_caching_min_ttl = optional(number)<br>    response_code         = optional(string)<br>    response_page = optional(object({<br>      source      = string<br>      path_prefix = string<br>    }))<br>  }))</pre> | `[]` | no |
| <a name="input_distribution"></a> [distribution](#input\_distribution) | Configuration for the CloudFront distribution | <pre>object({<br>    deployment   = optional(string, "CREATE")<br>    enabled      = optional(bool, true)<br>    ipv6_enabled = optional(bool, true)<br>    http_version = optional(string, "http2")<br>    price_class  = optional(string, "PriceClass_100")<br>    geo_restrictions = optional(object({<br>      type      = optional(string, "none"),<br>      locations = optional(list(string), [])<br>    }), {})<br>    x_forwarded_host_function = optional(object({<br>      runtime = optional(string)<br>      code    = optional(string)<br>    }), {})<br>    auth_function = optional(object({<br>      deployment = optional(string, "NONE")<br>      arn        = optional(string)<br>      deployment_artifact = optional(object({<br>        handler = optional(string)<br>        zip = optional(object({<br>          path = string<br>          hash = string<br>        }))<br>        s3 = optional(object({<br>          bucket         = string<br>          key            = string<br>          object_version = optional(string)<br>        }))<br>      }))<br>      runtime     = optional(string, "nodejs20.x")<br>      timeout     = optional(number, 10)<br>      memory_size = optional(number, 256)<br>      additional_iam_policies = optional(list(object({<br>        name   = string,<br>        arn    = optional(string)<br>        policy = optional(string)<br>      })), [])<br>      iam = optional(object({<br>        path                 = optional(string)<br>        permissions_boundary = optional(string)<br>      }))<br>      cloudwatch_log = optional(object({<br>        retention_in_days = number<br>      }))<br>      timeouts = optional(object({<br>        create = optional(string)<br>        update = optional(string)<br>        delete = optional(string)<br>      }), {})<br>    }), {})<br>  })</pre> | `{}` | no |
| <a name="input_domain_config"></a> [domain\_config](#input\_domain\_config) | Configuration for CloudFront distribution domain | <pre>object({<br>    evaluate_target_health = optional(bool, true)<br>    sub_domain             = optional(string)<br>    hosted_zones = list(object({<br>      name         = string<br>      id           = optional(string)<br>      private_zone = optional(bool, false)<br>    }))<br>    create_route53_entries = optional(bool, true)<br>    viewer_certificate = optional(object({<br>      acm_certificate_arn      = string<br>      ssl_support_method       = optional(string, "sni-only")<br>      minimum_protocol_version = optional(string, "TLSv1.2_2021")<br>    }))<br>  })</pre> | `null` | no |
| <a name="input_folder_path"></a> [folder\_path](#input\_folder\_path) | The path to the open next artifacts | `string` | n/a | yes |
| <a name="input_function_architecture"></a> [function\_architecture](#input\_function\_architecture) | The default instruction set architecture for the lambda functions. This can be overridden for each function | `string` | `"arm64"` | no |
| <a name="input_iam"></a> [iam](#input\_iam) | The default IAM configuration. This can be overridden for each function | <pre>object({<br>    path                 = optional(string, "/")<br>    permissions_boundary = optional(string)<br>  })</pre> | `{}` | no |
| <a name="input_image_optimisation_function"></a> [image\_optimisation\_function](#input\_image\_optimisation\_function) | Configuration for the image optimisation function | <pre>object({<br>    create = optional(bool, true)<br>    deployment_artifact = optional(object({<br>      handler = optional(string)<br>      zip = optional(object({<br>        path = string<br>        hash = string<br>      }))<br>      s3 = optional(object({<br>        bucket         = string<br>        key            = string<br>        object_version = optional(string)<br>      }))<br>    }))<br>    runtime                          = optional(string, "nodejs20.x")<br>    deployment                       = optional(string, "REGIONAL_LAMBDA")<br>    timeout                          = optional(number, 25)<br>    memory_size                      = optional(number, 1536)<br>    additional_environment_variables = optional(map(string), {})<br>    function_architecture            = optional(string)<br>    additional_iam_policies = optional(list(object({<br>      name   = string,<br>      arn    = optional(string)<br>      policy = optional(string)<br>    })), [])<br>    vpc = optional(object({<br>      security_group_ids = list(string),<br>      subnet_ids         = list(string)<br>    }))<br>    iam = optional(object({<br>      path                 = optional(string)<br>      permissions_boundary = optional(string)<br>    }))<br>    cloudwatch_log = optional(object({<br>      retention_in_days = number<br>    }))<br>    timeouts = optional(object({<br>      create = optional(string)<br>      update = optional(string)<br>      delete = optional(string)<br>    }), {})<br>  })</pre> | `{}` | no |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | A prefix which will be attached to the resource name to ensure resources are random | `string` | `null` | no |
| <a name="input_revalidation_function"></a> [revalidation\_function](#input\_revalidation\_function) | Configuration for the revalidation function | <pre>object({<br>    deployment_artifact = optional(object({<br>      handler = optional(string)<br>      zip = optional(object({<br>        path = string<br>        hash = string<br>      }))<br>      s3 = optional(object({<br>        bucket         = string<br>        key            = string<br>        object_version = optional(string)<br>      }))<br>    }))<br>    runtime                          = optional(string, "nodejs20.x")<br>    timeout                          = optional(number, 25)<br>    memory_size                      = optional(number, 1536)<br>    additional_environment_variables = optional(map(string), {})<br>    function_architecture            = optional(string)<br>    additional_iam_policies = optional(list(object({<br>      name   = string,<br>      arn    = optional(string)<br>      policy = optional(string)<br>    })), [])<br>    vpc = optional(object({<br>      security_group_ids = list(string),<br>      subnet_ids         = list(string)<br>    }))<br>    iam = optional(object({<br>      path                 = optional(string)<br>      permissions_boundary = optional(string)<br>    }))<br>    cloudwatch_log = optional(object({<br>      retention_in_days = number<br>    }))<br>    timeouts = optional(object({<br>      create = optional(string)<br>      update = optional(string)<br>      delete = optional(string)<br>    }), {})<br>  })</pre> | `{}` | no |
| <a name="input_s3_exclusion_regex"></a> [s3\_exclusion\_regex](#input\_s3\_exclusion\_regex) | A regex of files to exclude from the s3 copy | `string` | `null` | no |
| <a name="input_s3_folder_prefix"></a> [s3\_folder\_prefix](#input\_s3\_folder\_prefix) | An optional folder to store files under | `string` | `null` | no |
| <a name="input_server_function"></a> [server\_function](#input\_server\_function) | Configuration for the server function | <pre>object({<br>    deployment_artifact = optional(object({<br>      handler = optional(string)<br>      zip = optional(object({<br>        path = string<br>        hash = string<br>      }))<br>      s3 = optional(object({<br>        bucket         = string<br>        key            = string<br>        object_version = optional(string)<br>      }))<br>    }))<br>    runtime                          = optional(string, "nodejs20.x")<br>    deployment                       = optional(string, "REGIONAL_LAMBDA")<br>    timeout                          = optional(number, 10)<br>    memory_size                      = optional(number, 1024)<br>    function_architecture            = optional(string)<br>    additional_environment_variables = optional(map(string), {})<br>    additional_iam_policies = optional(list(object({<br>      name   = string,<br>      arn    = optional(string)<br>      policy = optional(string)<br>    })), [])<br>    vpc = optional(object({<br>      security_group_ids = list(string),<br>      subnet_ids         = list(string)<br>    }))<br>    iam = optional(object({<br>      path                 = optional(string)<br>      permissions_boundary = optional(string)<br>    }))<br>    cloudwatch_log = optional(object({<br>      retention_in_days = number<br>    }))<br>    timeouts = optional(object({<br>      create = optional(string)<br>      update = optional(string)<br>      delete = optional(string)<br>    }), {})<br>  })</pre> | `{}` | no |
| <a name="input_suffix"></a> [suffix](#input\_suffix) | A suffix which will be attached to the resource name to ensure resources are random | `string` | `null` | no |
| <a name="input_tag_mapping_db"></a> [tag\_mapping\_db](#input\_tag\_mapping\_db) | Configuration for the ISR tag mapping database | <pre>object({<br>    deployment     = optional(string, "CREATE")<br>    billing_mode   = optional(string, "PAY_PER_REQUEST")<br>    read_capacity  = optional(number)<br>    write_capacity = optional(number)<br>    revalidate_gsi = optional(object({<br>      read_capacity  = optional(number)<br>      write_capacity = optional(number)<br>    }), {})<br>  })</pre> | `{}` | no |
| <a name="input_vpc"></a> [vpc](#input\_vpc) | The default VPC configuration for the lambda resources. This can be overridden for each function | <pre>object({<br>    security_group_ids = list(string),<br>    subnet_ids         = list(string)<br>  })</pre> | `null` | no |
| <a name="input_waf"></a> [waf](#input\_waf) | Configuration for the CloudFront distribution WAF | <pre>object({<br>    deployment = optional(string, "NONE")<br>    web_acl_id = optional(string)<br>    aws_managed_rules = optional(list(object({<br>      priority              = optional(number)<br>      name                  = string<br>      aws_managed_rule_name = string<br>      })), [{<br>      name                  = "amazon-ip-reputation-list"<br>      aws_managed_rule_name = "AWSManagedRulesAmazonIpReputationList"<br>      }, {<br>      name                  = "common-rule-set"<br>      aws_managed_rule_name = "AWSManagedRulesCommonRuleSet"<br>      }, {<br>      name                  = "known-bad-inputs"<br>      aws_managed_rule_name = "AWSManagedRulesKnownBadInputsRuleSet"<br>    }])<br>    rate_limiting = optional(object({<br>      enabled = optional(bool, false)<br>      limits = optional(list(object({<br>        priority         = optional(number)<br>        rule_name_suffix = optional(string)<br>        limit            = optional(number, 1000)<br>        behaviour        = optional(string, "BLOCK")<br>        geo_match_scope  = optional(list(string))<br>      })), [])<br>    }), {})<br>    sqli = optional(object({<br>      enabled  = optional(bool, false)<br>      priority = optional(number)<br>    }), {})<br>    account_takeover_protection = optional(object({<br>      enabled              = optional(bool, false)<br>      priority             = optional(number)<br>      login_path           = string<br>      enable_regex_in_path = optional(bool)<br>      request_inspection = optional(object({<br>        username_field_identifier = string<br>        password_field_identifier = string<br>        payload_type              = string<br>      }))<br>      response_inspection = optional(object({<br>        failure_codes = list(string)<br>        success_codes = list(string)<br>      }))<br>    }))<br>    account_creation_fraud_prevention = optional(object({<br>      enabled                = optional(bool, false)<br>      priority               = optional(number)<br>      creation_path          = string<br>      registration_page_path = string<br>      enable_regex_in_path   = optional(bool)<br>      request_inspection = optional(object({<br>        email_field_identifier    = string<br>        username_field_identifier = string<br>        password_field_identifier = string<br>        payload_type              = string<br>      }))<br>      response_inspection = optional(object({<br>        failure_codes = list(string)<br>        success_codes = list(string)<br>      }))<br>    }))<br>    enforce_basic_auth = optional(object({<br>      enabled       = optional(bool, false)<br>      priority      = optional(number)<br>      response_code = optional(number, 401)<br>      response_header = optional(object({<br>        name  = optional(string, "WWW-Authenticate")<br>        value = optional(string, "Basic realm=\"Requires basic auth\"")<br>      }), {})<br>      header_name = optional(string, "authorization")<br>      credentials = optional(object({<br>        username = string<br>        password = string<br>      }))<br>      ip_address_restrictions = optional(list(object({<br>        action = optional(string, "BYPASS")<br>        arn    = optional(string)<br>        name   = optional(string)<br>      })))<br>    }))<br>    additional_rules = optional(list(object({<br>      enabled  = optional(bool, false)<br>      priority = optional(number)<br>      name     = string<br>      action   = optional(string, "COUNT")<br>      block_action = optional(object({<br>        response_code = number<br>        response_header = optional(object({<br>          name  = string<br>          value = string<br>        }))<br>        custom_response_body_key = optional(string)<br>      }))<br>      ip_address_restrictions = optional(list(object({<br>        action = optional(string, "BYPASS")<br>        arn    = optional(string)<br>        name   = optional(string)<br>      })))<br>    })))<br>    ip_addresses = optional(map(object({<br>      description        = optional(string)<br>      ip_address_version = string<br>      addresses          = list(string)<br>    })))<br>    custom_response_bodies = optional(list(object({<br>      key          = string<br>      content      = string<br>      content_type = string<br>    })))<br>  })</pre> | `{}` | no |
| <a name="input_warmer_function"></a> [warmer\_function](#input\_warmer\_function) | Configuration for the warmer function | <pre>object({<br>    enabled = optional(bool, false)<br>    warm_staging = optional(object({<br>      enabled     = optional(bool, false)<br>      concurrency = optional(number)<br>    }))<br>    deployment_artifact = optional(object({<br>      handler = optional(string)<br>      zip = optional(object({<br>        path = string<br>        hash = string<br>      }))<br>      s3 = optional(object({<br>        bucket         = string<br>        key            = string<br>        object_version = optional(string)<br>      }))<br>    }))<br>    runtime                          = optional(string, "nodejs20.x")<br>    concurrency                      = optional(number, 20)<br>    timeout                          = optional(number, 15 * 60) // 15 minutes<br>    memory_size                      = optional(number, 1024)<br>    function_architecture            = optional(string)<br>    schedule                         = optional(string, "rate(5 minutes)")<br>    additional_environment_variables = optional(map(string), {})<br>    additional_iam_policies = optional(list(object({<br>      name   = string,<br>      arn    = optional(string)<br>      policy = optional(string)<br>    })), [])<br>    vpc = optional(object({<br>      security_group_ids = list(string),<br>      subnet_ids         = list(string)<br>    }))<br>    iam = optional(object({<br>      path                 = optional(string)<br>      permissions_boundary = optional(string)<br>    }))<br>    cloudwatch_log = optional(object({<br>      retention_in_days = number<br>    }))<br>    timeouts = optional(object({<br>      create = optional(string)<br>      update = optional(string)<br>      delete = optional(string)<br>    }), {})<br>  })</pre> | `{}` | no |
| <a name="input_website_bucket"></a> [website\_bucket](#input\_website\_bucket) | Configuration for the website S3 bucket | <pre>object({<br>    deployment           = optional(string, "CREATE")<br>    create_bucket_policy = optional(bool, true)<br>    force_destroy        = optional(bool, false)<br>    arn                  = optional(string)<br>    region               = optional(string)<br>    name                 = optional(string)<br>    domain_name          = optional(string)<br>  })</pre> | `{}` | no |
| <a name="input_zone_suffix"></a> [zone\_suffix](#input\_zone\_suffix) | An optional zone suffix to add to the assets and cache folder to allow files to be loaded correctly | `string` | `null` | no |

### Outputs

| Name | Description |
|------|-------------|
| <a name="output_alias_details"></a> [alias\_details](#output\_alias\_details) | The alias config |
| <a name="output_alternate_domain_names"></a> [alternate\_domain\_names](#output\_alternate\_domain\_names) | Extra CNAMEs (alternate domain names) associated with the CloudFront distribution |
| <a name="output_behaviours"></a> [behaviours](#output\_behaviours) | The behaviours for the zone |
| <a name="output_bucket_arn"></a> [bucket\_arn](#output\_bucket\_arn) | The ARN of the s3 bucket |
| <a name="output_bucket_name"></a> [bucket\_name](#output\_bucket\_name) | The name of the s3 bucket |
| <a name="output_cloudfront_url"></a> [cloudfront\_url](#output\_cloudfront\_url) | The URL for the CloudFront distribution |
| <a name="output_custom_error_responses"></a> [custom\_error\_responses](#output\_custom\_error\_responses) | The custom error responses for the zone |
| <a name="output_zone_config"></a> [zone\_config](#output\_zone\_config) | The zone config |