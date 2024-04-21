# Backend Server Deployment Options

Several options exist to deploy the backend.

By default, all zones will use the same deployment options; however, you can override the deployment options for each zone. See the module documentation below for more information.

The backend options are as follows:

## Lambda function URLs (with no auth)

Lambda function URL (with no auth) is supported for both the Server and Image Optimisation functions. This is the default deployment model. To configure this, please add the following configuration.

```tf
...
server_function = {
  backend_deployment_type = "REGIONAL_LAMBDA"
  ...
}

image_optimisation_function = {
  backend_deployment_type = "REGIONAL_LAMBDA"
  ...
}
```

_Note:_ This will deploy the corresponding function without any auth

## Lambda function URL with IAM Auth (using CloudFront Origin Access Control)

CloudFront has added support for Origin Access Control for lambda function URLs. This is supported for both the Server and Image Optimisation functions. To configure this, please add the following configuration.

```tf
...
server_function = {
  backend_deployment_type = "REGIONAL_LAMBDA_WITH_OAC"
  ...
}

image_optimisation_function = {
  backend_deployment_type = "REGIONAL_LAMBDA_WITH_OAC"
  ...
}
```

**NOTE:** If you make a PUT or POST request to your backend, then the OAC might not be suitable as you must provide a signed payload as CloudFront doesn't currently support this; see [docs](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-restricting-access-to-lambda.html) for more details. If you see the following error: `The request signature we calculated does not match the signature you provided. Check your AWS Secret Access Key and signing method. Consult the service documentation for details.` you will either need to find a way to sign the body using an AWS Secret Access Key or use either the Lambda@edge auth function (backend_deployment_type = 'REGIONAL_LAMBDA_WITH_AUTH_LAMBDA') or do not have auth on the lambda URLs (backend_deployment_type = 'REGIONAL_LAMBDA')

## Lambda function URL with IAM Auth (using CloudFront Origin Access Control and allow any principal)

This deployment option has been included to allow users to safely migrate to using CloudFront OACs as the auth method for lambda URLs. Because resources are moving to prevent cyclic dependencies, there is a risk that requests will fail while the lambda permissions are updated and the CloudFront changes are propagating.

To mitigate this, a new backend deployment type, `REGIONAL_LAMBDA_WITH_OAC_AND_ANY_PRINCIPAL,` was introduced to allow you to have both any principal permitted (used for the auth function and public lambda URLs) and the OAC associated with the CloudFront distributions.

To configure this, please add the following configuration.

```tf
...
server_function = {
  backend_deployment_type = "REGIONAL_LAMBDA_WITH_OAC_AND_ANY_PRINCIPAL"
  ...
}

image_optimisation_function = {
  backend_deployment_type = "REGIONAL_LAMBDA_WITH_OAC_AND_ANY_PRINCIPAL"
  ...
}
```

**NOTE:** This is meant to aid with migrating server and image optimisation functions that were previously deployed with `REGIONAL_LAMBDA_WITH_AUTH_LAMBDA` or `REGIONAL_LAMBDA` to using `REGIONAL_LAMBDA_WITH_OAC`.

Assuming you already have resources deployed, you can update your server and image optimisation functions configuration to set the `backend_deployment_type` to `REGIONAL_LAMBDA_WITH_OAC_AND_ANY_PRINCIPAL`.

After applying this change, you can update your server and image optimisation functions configuration to set the `backend_deployment_type` to `REGIONAL_LAMBDA_WITH_OAC`. You must apply these changes to remove the permission to allow any principal to invoke the lambda.

## Lambda function URLs with IAM Auth (using lambda@edge auth function)

Some companies only allow lambda URLs to be configured with authorisation. Hence, AWS released a [blog post](https://aws.amazon.com/blogs/compute/protecting-an-aws-lambda-function-url-with-amazon-cloudfront-and-lambdaedge/) which demonstrated how you could use an auth function (running as lambda@edge) to generate the SigV4 required to call the sever function with the correct Authorisation header. To configure this, please add the following configuration.

```tf
...
server_function = {
  backend_deployment_type = "REGIONAL_LAMBDA_WITH_AUTH_LAMBDA"
  ...
}

image_optimisation_function = {
  backend_deployment_type = "REGIONAL_LAMBDA_WITH_AUTH_LAMBDA"
  ...
}
```

Using this deployment model does add additional resources and cost; however, this is a workaround until CloudFront natively supports generating signatures to call a lambda protected by IAM auth.

## Lambda@edge (server function only)

Please add the following configuration to run the server function as a lambda@edge function.

```tf
provider "aws" {
  alias = "server_function"
  region = "us-east-1" # For lambda@edge to be used, the region must be set to us-east-1
}

...
server_function = {
  backend_deployment_type = "EDGE_LAMBDA"
  ...
}
```

As lambda@edge does not support environment variables, the module will inject them at the top of the server code before it is uploaded to AWS. Credit to SST for the inspiration behind this. [Link](https://github.com/sst/sst/blob/3b792053d90c49d9ca693308646a3389babe9ceb/packages/sst/src/constructs/EdgeFunction.ts#L193)
