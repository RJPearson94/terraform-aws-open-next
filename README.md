# Open Next Terraform

This module deploys a next.js website using [Open Next](https://github.com/serverless-stack/open-next) to AWS utilising lambda, S3 and CloudFront.

This repo contains modules that let you build single-zone or multi-zone websites.

As part of v2 of the module, the monolithic [legacy](./modules/legacy) module was broken down into multiple modules to allow for additional configuration and deployment options. For some workloads, i.e. using open next 1.x or existing workloads, you must use the [legacy](./modules/legacy) module. 

If you want to take advantage of some of the new features, such as:

- Improved OpenNext 2.x support
  - Support for server actions (this is not supported with lambda@edge)
- More deployment and configuration options
- CloudFront continuous deployments
  - AWS Developer Guide - https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/continuous-deployment.html
  - AWS Blog - https://aws.amazon.com/blogs/networking-and-content-delivery/use-cloudfront-continuous-deployment-to-safely-validate-cdn-changes/
- Lambda function URLs with IAM Auth
  - using lambda@edge auth function - AWS Blog - https://aws.amazon.com/blogs/compute/protecting-an-aws-lambda-function-url-with-amazon-cloudfront-and-lambdaedge/
  - using Origin Access Control - AWS Blog - https://aws.amazon.com/blogs/networking-and-content-delivery/secure-your-lambda-function-urls-using-amazon-cloudfront-origin-access-control/
- WAF
    - Includes AWS recommended rules (AWSManagedRulesAmazonIpReputationList, AWSManagedRulesCommonRuleSet & AWSManagedRulesKnownBadInputsRuleSet)
    - Configure multiple IP rate-based rules
    - Configure SQL injection rules
    - Configure account takeover protection rules
    - Configure account creation fraud prevention rules
    - Configure basic auth 
        - This is inspired by Vercel's password-protected deployment feature - https://vercel.com/guides/how-do-i-add-password-protection-to-my-vercel-deployment
        - Credit to Shinji Nakamatu for this idea - https://dev.to/snaka/implementing-secure-access-control-using-aws-waf-with-ip-address-and-basic-authentication-45hn
    - Custom rules (with custom response bodies) i.e. add a maintenance page to take the website offline when maintenance is taking place
        - Credit to Paul L for this idea - https://repost.aws/questions/QUeXIw1g0hSxiF0BpugsT7aw/how-to-implement-the-maintenance-page-using-route-53-to-switch-between-cloudfront-distributions
    - Configure default action (with custom response bodies)
- Custom Error Pages

And more. Then please use 2.x or above of the module.

*Note:* V2 of the module requires you to use at least v2.0 of the open next library

If you only plan on using a single-zone deployment model, please use the [tf-aws-open-next-zone](./modules/tf-aws-open-next-zone) module. If you manage multiple zones in the same terraform state, please use the [tf-aws-open-next-multi-zone](./modules/tf-aws-open-next-multi-zone) module. Installation and module documentation can be found in the corresponding folders.

Where possible, the modules try to give you as many configuration options as possible; however, the module won't be able to cater for all use cases, so for the majority of components, you can curate your bespoke resources in Terraform, i.e. WAF, CloudFront distribution, etc. and pass the ARN of the resource to the module to use.

*Note:* These modules use multiple bash scripts to delete data, upload data and mutate resources outside of Terraform. This prevents Terraform from removing resources when they have changed and allows the staging distribution functionality to work correctly. You must have bash and the AWS CLI available, the CLI must be configured to use the same credentials or environment variables as the default AWS provider for this functionality to work correctly.

The module is available in the [Terraform registry](https://registry.terraform.io/modules/RJPearson94/open-next/aws/latest)

## Upgrading

### From 1.x to 2.x

#### Use v1/ legacy module

The v1, also known as the legacy module, has been kept to ensure that you can continue to use the module and receive some updates (will be determined on a case-by-case basis); you may want to use this instead of adopting the newer features. To use the legacy module, please add the following code. The existing variables and inputs have been retained.

```tf
module "legacy" {
  source  = "RJPearson94/open-next/aws//modules/legacy"
  version = ">= 2.0.0, < 3.0.0"

  ... 
}
```

#### Use new single-zone or multi-zone module

When upgrading to v2 of the module, it is recommended that you redeploy your application into a new Terraform state and then shift traffic over due to the number of changes compared to the legacy module. If this is not possible, you can attempt to import the existing resources into your terraform state. See the [terraform docs](https://developer.hashicorp.com/terraform/language/state/import) for more information

### From 2.x to 3.x

Where possible, the module has been made backwards compatible with 2.x.

For open next v3, the module will read the `open-next.output.json` file in the .open-next directory to determine the edge and server functions that need to be configured, with any default configuration i.e streaming that needs to be configured.

**NOTE:** Deprecated fields have been removed. If you use one of the following values, you will need to modify your Terraform/ Terragrunt configuration 

- `EDGE_LAMBDA` backend deployment type is no longer supported for server function, in open next v3 this has been moved into edge functions instead [BREAKING CHANGE]
- `aws_lambda_permission.server_function_url_permission` and `aws_lambda_permission.image_optimisation_function_url_permission` have been merged into a list of `aws_lambda_permission.function_url_permission` resources in the `tf-aws-open-next-multi-zone` module. You can either let the resources re-create or update the references using either [move config](https://developer.hashicorp.com/terraform/tutorials/configuration-language/move-config), [import block](https://developer.hashicorp.com/terraform/language/import) or [import command](https://developer.hashicorp.com/terraform/cli/commands/import) [BREAKING CHANGE]
- CloudFront cache policy ARN - you must now set the CloudFront Cache Policy ID
- Auth function cloudfront log group - this configuration had no affect so has been removed

If you are still using open next v2.x, you can set the `open_next_version` variable to `v2.x.x` (the default value). If you upgrade to Open Next v3.x, please set the `open_next_version` variable to `v3.x.x`.

## Deployment options

Below are diagrams of the possible architecture combinations that can configured using v2 of this module. For each of the architectures, the following components are optional:

- Route 53 (A and AAAA records)
- WAF
- Staging Distribution
- Warmer function
- Image Optimisation function
- Tag to Path Mapping DB

### Single Zone

![Single Zone Complete](https://raw.githubusercontent.com/RJPearson94/terraform-aws-open-next/v2.4.1/docs/diagrams/Single%20Zone.png)

#### Terraform

```tf
data "aws_caller_identity" "current" {}

module "single_zone" {
  source  = "RJPearson94/open-next/aws//modules/tf-aws-open-next-zone"
  version = ">= 2.0.0, < 3.0.0"

  prefix = "open-next-${data.aws_caller_identity.current.account_id}"
  folder_path = "./.open-next"
}
```

#### Terragrunt

```hcl
terraform {
  source          = "tfr://registry.terraform.io/RJPearson94/open-next/aws//modules/tf-aws-open-next-zone?version=v2.4.1"
  include_in_copy = ["./.open-next"]
}

inputs = {
  prefix = "open-next-${get_aws_account_id()}"
  folder_path = "./.open-next"
}
```

### Multi-Zone - Independent Zones

![Multi Zone - Independent Zones](https://raw.githubusercontent.com/RJPearson94/terraform-aws-open-next/v2.4.1/docs/diagrams/Multi%20Zone%20-%20Independent%20Zones.png)

#### Terraform

```tf
data "aws_caller_identity" "current" {}

module "independent_zones" {
  source  = "RJPearson94/open-next/aws//modules/tf-aws-open-next-multi-zone"
  version = ">= 2.0.0, < 3.0.0"

  prefix = "open-next-ind-${data.aws_caller_identity.current.account_id}"
  deployment = "INDEPENDENT_ZONES"

  zones = [{
    root = true
    name = "home"
    folder_path = "./home/.open-next"
  },{
    root = false
    name = "docs"
    folder_path = "./docs/.open-next"
  }]
}
```

#### Terragrunt

```hcl
terraform {
  source          = "tfr://registry.terraform.io/RJPearson94/open-next/aws//modules/tf-aws-open-next-multi-zone?version=v2.4.1"
  include_in_copy = ["./docs/.open-next", "./home/.open-next"]
}

inputs = {
  prefix = "open-next-ind-${get_aws_account_id()}"
  deployment = "INDEPENDENT_ZONES"

  zones = [{
    root = true
    name = "home"
    folder_path = "./home/.open-next"
  },{
    root = false
    name = "docs"
    folder_path = "./docs/.open-next"
  }]
}
```

_Note:_ If you use tools like Terragrunt or CDKTF, you can use the Single Zone module to deploy each zone into its own terraform state

### Multi-Zone - Shared Distribution

![Multi Zone - Shared Distribution](https://raw.githubusercontent.com/RJPearson94/terraform-aws-open-next/v2.4.1/docs/diagrams/Multi%20Zone%20-%20Shared%20Distribution.png)

#### Terraform

```tf
data "aws_caller_identity" "current" {}

module "shared_distribution" {
  source  = "RJPearson94/open-next/aws//modules/tf-aws-open-next-multi-zone"
  version = ">= 2.0.0, < 3.0.0"

  prefix = "open-next-sd-${data.aws_caller_identity.current.account_id}"
  deployment = "SHARED_DISTRIBUTION"

  zones = [{
    root = true
    name = "home"
    folder_path = "./home/.open-next"
  },{
    root = false
    name = "docs"
    folder_path = "./docs/.open-next"
  }]
}
```

#### Terragrunt

```hcl
terraform {
  source          = "tfr://registry.terraform.io/RJPearson94/open-next/aws//modules/tf-aws-open-next-multi-zone?version=v2.4.1"
  include_in_copy = ["./docs/.open-next", "./home/.open-next"]
}

inputs = {
  prefix = "open-next-sd-${get_aws_account_id()}"
  deployment = "SHARED_DISTRIBUTION"

  zones = [{
    root = true
    name = "home"
    folder_path = "./home/.open-next"
  },{
    root = false
    name = "docs"
    folder_path = "./docs/.open-next"
  }]
}
```

### Multi-Zone - Shared Distribution and Bucket

![Multi Zone - Shared Distribution and Bucket](https://raw.githubusercontent.com/RJPearson94/terraform-aws-open-next/v2.4.1/docs/diagrams/Multi%20Zone%20-%20Shared%20Distribution%20and%20Bucket.png)

#### Terraform

```tf
data "aws_caller_identity" "current" {}

module "shared_distribution_and_bucket" {
  source  = "RJPearson94/open-next/aws//modules/tf-aws-open-next-multi-zone"
  version = ">= 2.0.0, < 3.0.0"

  prefix = "open-next-sb-${data.aws_caller_identity.current.account_id}"
  deployment = "SHARED_DISTRIBUTION_AND_BUCKET"

  zones = [{
    root = true
    name = "home"
    folder_path = "./home/.open-next"
  },{
    root = false
    name = "docs"
    folder_path = "./docs/.open-next"
  }]
}
```

#### Terragrunt

```hcl
terraform {
  source          = "tfr://registry.terraform.io/RJPearson94/open-next/aws//modules/tf-aws-open-next-multi-zone?version=2.0.2"
  include_in_copy = ["./docs/.open-next", "./home/.open-next"]
}

inputs = {
  prefix = "open-next-sb-${get_aws_account_id()}"
  deployment = "SHARED_DISTRIBUTION_AND_BUCKET"

  zones = [{
    root = true
    name = "home"
    folder_path = "./home/.open-next"
  },{
    root = false
    name = "docs"
    folder_path = "./docs/.open-next"
  }]
}
```

## Custom Domains

For infomation on managing custom domains see the [domain config documentation](https://github.com/RJPearson94/terraform-aws-open-next/blob/v2.4.1/docs/domain-config.md)

## Examples

The examples have been moved to a separate repository to reduce the amount of code that Terraform downloads. You can find them at [RJPearson94/terraform-aws-open-next-examples repo](https://github.com/RJPearson94/terraform-aws-open-next-examples)
