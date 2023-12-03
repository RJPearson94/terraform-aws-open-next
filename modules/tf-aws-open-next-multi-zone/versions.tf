terraform {
  required_version = ">= 1.4.0"

  required_providers {
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.3.0"
    }
    aws = {
      source                = "hashicorp/aws"
      version               = ">= 5.26.0"
      configuration_aliases = [aws.server_function, aws.iam, aws.dns]
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.4.0"
    }
    terraform = {
      source = "terraform.io/builtin/terraform"
    }
  }
}
