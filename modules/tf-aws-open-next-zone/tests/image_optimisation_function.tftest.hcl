# Plan-only tests: every provider is mocked, so no AWS credentials are needed
# and nothing is created. Run from modules/tf-aws-open-next-zone with
# `terraform test` (Terraform >= 1.7 for mock providers).

mock_provider "aws" {}

mock_provider "aws" {
  alias = "server_function"
}

mock_provider "aws" {
  alias = "iam"
}

mock_provider "aws" {
  alias = "dns"
}

mock_provider "aws" {
  alias = "global"
}

mock_provider "archive" {}

mock_provider "local" {}

variables {
  prefix            = "test"
  folder_path       = "./tests/fixtures/.open-next"
  open_next_version = "v3.x.x"

  # The CloudFront managed-policy data sources expose `id` as a non-computed
  # attribute, so mocks leave it null and the module's coalesce() fallbacks
  # fail. Passing the IDs directly skips those lookups.
  behaviours = {
    server = {
      origin_request_policy_id = "b689b0a8-53d0-40ab-baf2-68738e2966ac"
    }
    image_optimisation = {
      origin_request_policy_id = "b689b0a8-53d0-40ab-baf2-68738e2966ac"
    }
    static_assets = {
      cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    }
  }
}

run "image_optimisation_origin_is_created_by_default" {
  command = plan

  assert {
    condition     = contains(keys(output.zone_config.origins), "image_optimisation")
    error_message = "Expected an image_optimisation origin when image_optimisation_function.create is true"
  }

  assert {
    condition     = length(module.image_optimisation_function) == 1
    error_message = "Expected the image optimisation function to be created"
  }
}

run "image_optimisation_origin_is_omitted_when_create_is_false" {
  command = plan

  variables {
    image_optimisation_function = {
      create = false
    }
  }

  assert {
    condition     = !contains(keys(output.zone_config.origins), "image_optimisation")
    error_message = "Expected no image_optimisation origin when image_optimisation_function.create is false"
  }

  assert {
    condition     = length(module.image_optimisation_function) == 0
    error_message = "Expected the image optimisation function not to be created"
  }

  assert {
    condition     = length(aws_lambda_permission.image_optimisation_function_url_permission) == 0
    error_message = "Expected no CloudFront invoke permissions for the image optimisation function"
  }
}

run "oac_image_origin_is_omitted_when_create_is_false" {
  command = plan

  variables {
    image_optimisation_function = {
      create                  = false
      backend_deployment_type = "REGIONAL_LAMBDA_WITH_OAC"
    }
  }

  assert {
    condition     = !contains(keys(output.zone_config.origins), "image_optimisation")
    error_message = "Expected no image_optimisation origin when image_optimisation_function.create is false"
  }
}
