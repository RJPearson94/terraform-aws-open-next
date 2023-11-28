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

  dynamic "vpc_config" {
    for_each = var.vpc != null ? [var.vpc] : []

    content {
      security_group_ids = vpc_config.value["security_group_ids"]
      subnet_ids         = vpc_config.value["subnet_ids"]
    }
  }

  timeouts {
    create = try(var.timeouts.create, null)
    update = try(var.timeouts.update, null)
    delete = try(var.timeouts.delete, null)
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
      ],
      var.vpc != null ? [
        {
          "Action" : [
            "ec2:CreateNetworkInterface",
            "ec2:DescribeNetworkInterfaces",
            "ec2:DeleteNetworkInterface",
            "ec2:AssignPrivateIpAddresses",
            "ec2:UnassignPrivateIpAddresses"
          ],
          "Resource" : "*"
          "Effect" : "Allow"
        }
      ] : [],
    var.iam_policy_statements)
  })
}

resource "aws_iam_role_policy_attachment" "policy_attachment" {
  role       = aws_iam_role.lambda_iam.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "aws_iam_policy" "additional_policy" {
  for_each = {
    for additional_iam_policy in var.additional_iam_policies : additional_iam_policy.name => additional_iam_policy if additional_iam_policy.policy != null
  }
  name = "${var.prefix}${var.function_name}-${each.key}${var.suffix}"
  path = var.iam.path

  policy = each.value.policy
}

resource "aws_iam_role_policy_attachment" "additional_policy_attachment" {
  for_each = {
    for additional_iam_policy in var.additional_iam_policies : additional_iam_policy.name => additional_iam_policy
  }
  role       = aws_iam_role.lambda_iam.name
  policy_arn = each.value.arn != null ? each.value.arn : aws_iam_policy.additional_policy[each.key].arn
}
