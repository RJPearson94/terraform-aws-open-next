# Backend Server Deployment Options

Several options exist to deploy the backend.

By default all zones will use the same deployment options however you can override the deployment options for each zone. See the module documentation below for more information

The backend options are as follows:

## Lambda function URLs (with no auth)

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

_Note:_ This will deploy the corresponding function without any auth

## Lambda function URLs with IAM Auth (using lambda@edge auth function)

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

## Lambda@edge (server function only)

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

As lambda@edge does not support environment variables, the module will inject them at the top of the server code before it is uploaded to AWS. Credit to SST for the inspiration behind this. [Link](https://github.com/sst/sst/blob/3b792053d90c49d9ca693308646a3389babe9ceb/packages/sst/src/constructs/EdgeFunction.ts#L193)
