# Open Next Terraform

This module deploys a next.js website using [Open Next](https://github.com/serverless-stack/open-next) to AWS utilising lambda, S3 and CloudFront.

This repo contains modules that let you build single-zone or multi-zone websites.

As part of v2 of the module, the monolithic [legacy](./modules/legacy) module was broken down into multiple modules to allow for greater configuration and deployment options. For some workloads, i.e. using open next 1.x or existing workloads, you must use the [legacy](./modules/legacy) module. Please see the [README](./modules/legacy/README.md) in that folder for the installation instructions

If you want to take advantage of some of the new features, such as:

- Improved OpenNext 2.x support
  - Support for server actions (this is not supported with lambda@edge)
- More deployment and configuration options
- CloudFront continuous deployments
  - AWS Developer Guide - https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/continuous-deployment.html
  - AWS Blog - https://aws.amazon.com/blogs/networking-and-content-delivery/use-cloudfront-continuous-deployment-to-safely-validate-cdn-changes/
- Lambda function URLs with IAM Auth (using lambda@edge auth function)
  - AWS Blog - https://aws.amazon.com/blogs/compute/protecting-an-aws-lambda-function-url-with-amazon-cloudfront-and-lambdaedge/
- WAF
    - Includes AWS recommended rules (AWSManagedRulesAmazonIpReputationList, AWSManagedRulesCommonRuleSet & AWSManagedRulesKnownBadInputsRuleSet)
    - Configure multiple IP rate based rules
    - Configure SQL injection rules
    - Configure account takeover protection rules
    - Configure account creation fraud prevention rules
    - Configure basic auth 
        - This is inspired by Vercel's password protected deployment feature - https://vercel.com/guides/how-do-i-add-password-protection-to-my-vercel-deployment
        - Credit to Shinji Nakamatu for this idea - https://dev.to/snaka/implementing-secure-access-control-using-aws-waf-with-ip-address-and-basic-authentication-45hn
    - Custom rules (with custom response bodies) i.e. add a maintainance page to take the website offline when maintainance is taking place
        - Credit to Paul L for this idea - https://repost.aws/questions/QUeXIw1g0hSxiF0BpugsT7aw/how-to-implement-the-maintenance-page-using-route-53-to-switch-between-cloudfront-distributions
- Custom Error Pages

And more. Then please use 2.x of the module.

*Note:* V2 of the module requires you to use at least v2.0 of the open next library

If you only plan on using a single-zone deployment model, please use the [tf-aws-open-next-zone](./modules/tf-aws-open-next-zone) module. If you manage multiple zones in the same terraform state, please use the [tf-aws-open-next-multi-zone](./modules/tf-aws-open-next-multi-zone) module. Installation and module documentation can be found in the corresponding folders.

Where possible, the modules try to give you as many configuration options as possible; however, the module won't be able to cater for all use cases, so for the majority of components, you can curate your bespoke resources in Terraform, i.e. WAF, CloudFront distribution, etc. and pass the ARN of the resource to the module to use.

The module is available in the [Terraform registry](https://registry.terraform.io/modules/RJPearson94/open-next/aws/latest)

## Deployment options

Below are diagrams of the possible architecture combinations that can configured using v2 of this module. For each of the architectures, the following components are optional:

- Route 53 (A and AAAA records)
- WAF
- Staging Distribution
- Warmer function
- Image Optimisation function
- Tag to Path Mapping DB

### Single Zone

![Single Zone Complete](./docs/diagrams/Single%20Zone.png)

### Multi-Zone - Independent Zones

![Multi Zone - Independent Zones](./docs/diagrams/Multi%20Zone%20-%20Independent%20Zones.png)

_Note:_ If you use tools like Terragrunt or CDKTF, you can use the Single Zone module to deploy each zone into its own terraform state

### Multi-Zone - Shared Distribution

![Multi Zone - Shared Distribution](./docs/diagrams/Multi%20Zone%20-%20Shared%20Distribution.png)

### Multi-Zone - Shared Distribution and Bucket

![Multi Zone - Shared Distribution](./docs/diagrams/Multi%20Zone%20-%20Shared%20Distribution%20and%20Bucket.png)

## Examples

The examples have been moved to a separate repository to reduce the amount of code that Terraform downloads. You can find them at [terraform-aws-open-next-examples repo](https://github.com/RJPearson94/terraform-aws-open-next-examples)
