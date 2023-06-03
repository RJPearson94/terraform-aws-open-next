# Lambda

resource "aws_lambda_function" "lambda_function" {
  filename         = var.zip_file
  source_code_hash = var.hash

  function_name = "${var.prefix}${var.function_name}${var.suffix}"
  role          = aws_iam_role.lambda_iam.arn

  runtime     = var.runtime
  handler     = var.handler
  memory_size = var.memory_size
  timeout     = var.timeout

  architectures = [var.architecture]
  publish       = var.publish

  environment {
    variables = var.environment_variables
  }
}

resource "aws_lambda_function_url" "function_url" {
  count = var.function_url.create ? 1 : 0

  function_name      = aws_lambda_function.lambda_function.function_name
  authorization_type = var.function_url.authorization_type
  invoke_mode        = "BUFFERED"
}

resource "aws_lambda_permission" "function_url_permission" {
  count = var.function_url.create ? 1 : 0

  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.lambda_function.function_name
  principal              = "*"
  function_url_auth_type = var.function_url.authorization_type
}

# Cloudwatch Logs

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  count             = var.run_at_edge ? 0 : 1
  name              = "/aws/lambda/${var.prefix}${var.function_name}${var.suffix}"
  retention_in_days = var.cloudwatch_log.retention_in_days
}

# IAM

resource "aws_iam_role" "lambda_iam" {
  name                 = "${var.prefix}${var.function_name}-role${var.suffix}"
  path                 = var.iam.path
  permissions_boundary = var.iam.permissions_boundary

  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : concat([
      {
        "Action" : "sts:AssumeRole",
        "Principal" : {
          "Service" : "lambda.amazonaws.com"
        },
        "Effect" : "Allow"
      }
      ], var.run_at_edge ? [
      {
        "Action" : "sts:AssumeRole",
        "Principal" : {
          "Service" : "edgelambda.amazonaws.com"
        },
        "Effect" : "Allow"
      }
    ] : [])
  })
}

resource "aws_iam_policy" "lambda_policy" {
  name = "${var.prefix}${var.function_name}-lambda-policy${var.suffix}"
  path = var.iam.path

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : concat([
      {
        "Action" : concat([
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ], var.run_at_edge ? ["logs:CreateLogGroup"] : []),
        "Resource" : var.run_at_edge ? "*" : "${one(aws_cloudwatch_log_group.lambda_log_group[*].arn)}:*",
        "Effect" : "Allow"
      }
    ], var.iam_policy_statements)
  })
}

resource "aws_iam_role_policy_attachment" "policy_attachment" {
  role       = aws_iam_role.lambda_iam.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}
