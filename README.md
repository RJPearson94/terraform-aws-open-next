# Open Next Terraform

This module is used to deploy a next.js website using [Open Next](https://github.com/serverless-stack/open-next) to AWS utilising lambda, S3 and CloudFront.

This module will build the corresponding resources to host the single-zone or multi-zone website, there are a number of options to deploy the backend. The options are:

- Lambda function URLs (with no auth)
- HTTP API Gateway (with proxy integrations to lambda functions)
- Lambda@edge (server function only)

**NOTE:** If lambda@edge is used, then the warmer function is not deployed

The script to invalidate the CloudFront distribution used bash and [jq](https://github.com/jqlang/jq). The invalidation script and Terraform apply will fail if the script fails to run.

## Examples

Examples of how the Terraform module can be used can be found [here](./examples)

To be able to run the examples, you will need to install the dependencies and build the websites using open-next. 

**NOTE:** You will need node 18 or above installed to build the applications

For the multi-zone website please run the following commands

```shell
cd examples/multi-zone/docs
yarn install
yarn build:open-next

...

cd ../home
yarn install
yarn build:open-next
```

For the single-zone website please run the following commands

```shell
cd examples/single-zone
yarn install
yarn build:open-next
```

## Module documentation

Below is the documentation for the Terraform module, outline the providers, modules and resources that are used. The documentation includes the inputs that can be supplied (including any defaults) and what is returned from the module

**NOTE:** The module will zip all the necessary open-next artifacts as part of a Terraform deploy. To facilitate this the .open-next folders need to be stored locally.

### Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.4.0 |
| <a name="requirement_archive"></a> [archive](#requirement\_archive) | >= 2.3.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 4.67.0 |

### Providers

| Name | Version |
|------|---------|
| <a name="provider_archive"></a> [archive](#provider\_archive) | >= 2.3.0 |
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 4.67.0 |
| <a name="provider_aws.dns"></a> [aws.dns](#provider\_aws.dns) | >= 4.67.0 |
| <a name="provider_aws.server_function"></a> [aws.server_function](#provider\_aws.server_function) | >= 4.67.0 |
| <a name="provider_aws.iam"></a> [aws.iam](#provider\_aws.iam) | >= 4.67.0 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

### Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_image_optimisation_function"></a> [image\_optimisation\_function](#module\_image\_optimisation\_function) | ./modules/tf-aws-lambda | n/a |
| <a name="module_server_function"></a> [server\_function](#module\_server\_function) | ./modules/tf-aws-lambda | n/a |
| <a name="module_warmer_function"></a> [warmer\_function](#module\_warmer\_function) | ./modules/tf-aws-scheduled-lambda | n/a |

### Resources

| Name | Type |
|------|------|
| [aws_apigatewayv2_api.api](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_api) | resource |
| [aws_apigatewayv2_deployment.deployment](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_deployment) | resource |
| [aws_apigatewayv2_stage.stable](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_stage) | resource |
| [aws_cloudfront_cache_policy.cache_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_cache_policy) | resource |
| [aws_cloudfront_distribution.website_distribution](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_distribution) | resource |
| [aws_cloudfront_function.x_forwarded_host](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_function) | resource |
| [aws_cloudfront_origin_access_control.website_origin_access_control](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_origin_access_control) | resource |
| [aws_lambda_permission.image_optimisation_function_permission](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_permission) | resource |
| [aws_lambda_permission.server_function_permission](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_permission) | resource |
| [aws_route53_record.route53_a_record](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_record.route53_aaaa_record](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_s3_bucket.website_bucket](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_policy.website_bucket_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_object.website_asset](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object) | resource |
| terraform_data.invalidate_distribution | resource |
| [archive_file.image_optimization_function](https://registry.terraform.io/providers/hashicorp/archive/latest/docs/data-sources/file) | data source |
| [archive_file.server_function](https://registry.terraform.io/providers/hashicorp/archive/latest/docs/data-sources/file) | data source |
| [archive_file.warmer_function](https://registry.terraform.io/providers/hashicorp/archive/latest/docs/data-sources/file) | data source |
| [aws_cloudfront_cache_policy.caching_optimized](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/cloudfront_cache_policy) | data source |
| [aws_cloudfront_origin_request_policy.all_viewer_except_host_header](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/cloudfront_origin_request_policy) | data source |
| [aws_route53_zone.hosted_zone](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/route53_zone) | data source |

### Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cache_control_immutable_assets_regex"></a> [cache\_control\_immutable\_assets\_regex](#input\_cache\_control\_immutable\_assets\_regex) | Regex to set public,max-age=31536000,immutable on immutable resources | `string` | `"^.*(\\.js|\\.css|\\.woff2)$"` | no |
| <a name="input_cloudfront"></a> [cloudfront](#input\_cloudfront) | Configuration for the cloudfront distribution | <pre>object({<br>    enabled                  = optional(bool, true)<br>    invalidate_on_change     = optional(bool, true)<br>    minimum_protocol_version = optional(string, "TLSv1.2_2021")<br>    ssl_support_method       = optional(string, "sni-only")<br>    http_version             = optional(string, "http2and3")<br>    ipv6_enabled             = optional(bool, true)<br>    price_class              = optional(string, "PriceClass_100")<br>    geo_restrictions = optional(object({<br>      type      = optional(string, "none"),<br>      locations = optional(list(string), [])<br>    }), {})<br>  })</pre> | `{}` | no |
| <a name="input_cloudwatch_log"></a> [cloudwatch\_log](#input\_cloudwatch\_log) | Override the Cloudwatch logs configuration | <pre>object({<br>    retention_in_days = number<br>  })</pre> | <pre>{<br>  "retention_in_days": 7<br>}</pre> | no |
| <a name="input_content_types"></a> [content\_types](#input\_content\_types) | The MIME type mapping and default for artifacts generated by Open Next | <pre>object({<br>    mapping = optional(map(string), {<br>      "svg" = "image/svg+xml",<br>      "js"  = "application/javascript",<br>      "css" = "text/css",<br>    })<br>    default = optional(string, "binary/octet-stream")<br>  })</pre> | `{}` | no |
| <a name="input_domain"></a> [domain](#input\_domain) | Configuration to for attaching a custom domain to the cloudfront distribution | <pre>object({<br>    create                 = optional(bool, false)<br>    hosted_zone_name       = optional(string),<br>    name                   = optional(string),<br>    alternate_names        = optional(list(string), [])<br>    acm_certificate_arn    = optional(string),<br>    evaluate_target_health = optional(bool, false)<br>  })</pre> | `{}` | no |
| <a name="input_iam"></a> [iam](#input\_iam) | Override the default IAM configuration | <pre>object({<br>    path                 = optional(string, "/")<br>    permissions_boundary = optional(string)<br>  })</pre> | `{}` | no |
| <a name="input_image_optimisation_function"></a> [image\_optimisation\_function](#input\_image\_optimisation\_function) | Configuration for the image optimisation function | <pre>object({<br>    runtime     = optional(string, "nodejs18.x")<br>    deployment  = optional(string, "REGIONAL_LAMBDA")<br>    timeout     = optional(number, 25)<br>    memory_size = optional(number, 1536)<br>  })</pre> | `{}` | no |
| <a name="input_open_next"></a> [open\_next](#input\_open\_next) | The next.js website config for single and multi-zone deployments | <pre>object({<br>    exclusion_regex  = optional(string)<br>    root_folder_path = string<br>    additional_zones = optional(list(object({<br>      name        = string<br>      http_path   = string<br>      folder_path = string<br>    })), [])<br>  })</pre> | n/a | yes |
| <a name="input_preferred_architecture"></a> [preferred\_architecture](#input\_preferred\_architecture) | Preferred instruction set architecture for the lambda function. If lambda@edge is used for the server function the architecture will be set to x86_64 for that function | `string` | `"arm64"` | no |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | A prefix which will be attached to resource name to esnure resources are random | `string` | `null` | no |
| <a name="input_server_function"></a> [server\_function](#input\_server\_function) | Configuration for the server function | <pre>object({<br>    runtime     = optional(string, "nodejs18.x")<br>    deployment  = optional(string, "REGIONAL_LAMBDA")<br>    timeout     = optional(number, 10)<br>    memory_size = optional(number, 1024)<br>  })</pre> | `{}` | no |
| <a name="input_suffix"></a> [suffix](#input\_suffix) | A suffix which will be attached to resource name to esnure resources are random | `string` | `null` | no |
| <a name="input_warmer_function"></a> [warmer\_function](#input\_warmer\_function) | Configuration for the warmer function | <pre>object({<br>    create      = bool<br>    runtime     = optional(string, "nodejs18.x")<br>    concurrency = optional(number, 20)<br>    timeout     = optional(number, 15 * 60) // 15 minutes<br>    memory_size = optional(number, 1024)<br>    schedule    = optional(string, "rate(5 minutes)")<br>  })</pre> | <pre>{<br>  "create": false<br>}</pre> | no |

### Outputs

| Name | Description |
|------|-------------|
| <a name="output_cloudfront_url"></a> [cloudfront\_url](#output\_cloudfront\_url) | The URL for the cloudfront distribution |
| <a name="output_domain_names"></a> [domain\_names](#output\_domain\_names) | The custom domain names attached to the cloudfront distribution |