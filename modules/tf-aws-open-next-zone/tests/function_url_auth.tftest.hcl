mock_provider "aws" {
  # Read back by tf-aws-open-next-aliases to pick the production/staging alias.
  mock_data "aws_ssm_parameter" {
    defaults = {
      insecure_value = "{\"production\":\"nextjs\",\"staging\":null}"
    }
  }
}

mock_provider "aws" {
  alias = "server_function"
}

mock_provider "aws" {
  alias = "iam"

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/mock"
    }
  }
  mock_resource "aws_iam_policy" {
    defaults = {
      arn = "arn:aws:iam::123456789012:policy/mock"
    }
  }
}

mock_provider "aws" {
  alias = "dns"
}

mock_provider "aws" {
  alias = "global"

  mock_resource "aws_cloudfront_function" {
    defaults = {
      arn = "arn:aws:cloudfront::123456789012:function/mock"
    }
  }
  mock_resource "aws_cloudfront_distribution" {
    defaults = {
      arn = "arn:aws:cloudfront::123456789012:distribution/EMOCK"
    }
  }
}

mock_provider "archive" {}
mock_provider "local" {}

variables {
  folder_path = "./tests/fixtures/.open-next"

  # The module's local-exec scripts call the AWS CLI; run them as no-ops.
  scripts = {
    interpreter = "true"
  }

  # Mocked data sources return a null id for the managed CloudFront policies,
  # so pass explicit ids instead of relying on the lookups.
  behaviours = {
    static_assets = {
      cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    }
    server = {
      origin_request_policy_id = "b689b0a8-53d0-40ab-baf2-68738e2966ac"
    }
    image_optimisation = {
      origin_request_policy_id = "b689b0a8-53d0-40ab-baf2-68738e2966ac"
    }
  }
}

# authorization_type is derived from backend_deployment_type. For types without
# an auth option (e.g. the default REGIONAL_LAMBDA), Terraform 1.16+ used to
# leave it unknown, failing apply with "Configuration contains unknown value".
run "regional_lambda" {
  command = apply
}

run "regional_lambda_with_oac" {
  command = apply

  variables {
    server_function = {
      backend_deployment_type = "REGIONAL_LAMBDA_WITH_OAC"
    }
    image_optimisation_function = {
      backend_deployment_type = "REGIONAL_LAMBDA_WITH_OAC_AND_ANY_PRINCIPAL"
    }
  }
}
