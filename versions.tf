terraform {
  required_version = ">= 1.4.0"

  required_providers {
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.3.0"
    }
    aws = {
      source                = "hashicorp/aws"
      version               = ">= 4.67.0"
      configuration_aliases = [aws.server_function, aws.iam, aws.dns]
    }
    terraform = {
      source = "terraform.io/builtin/terraform"
    }
  }
}
