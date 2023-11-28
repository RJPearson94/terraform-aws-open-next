locals {
  prefix = var.prefix == null ? "" : "${var.prefix}-"
  suffix = var.suffix == null ? "" : "-${var.suffix}"

  should_use_zip      = var.deployment_package.zip != null
  trigger_on_schedule = var.schedule != null

  alias_names = var.aliases.create ? var.aliases.names : []
}

# Lambda

resource "aws_lambda_function" "lambda_function" {
  filename          = local.should_use_zip ? try(var.deployment_package.zip.path) : null
  source_code_hash  = local.should_use_zip ? try(var.deployment_package.zip.hash) : null
  s3_bucket         = local.should_use_zip ? null : try(var.deployment_package.s3.bucket)
  s3_key            = local.should_use_zip ? null : try(var.deployment_package.s3.key)
  s3_object_version = local.should_use_zip ? null : try(var.deployment_package.s3.object_version)

  function_name = "${local.prefix}${var.function_name}${local.suffix}"
  role          = aws_iam_role.lambda_iam.arn

  runtime     = var.runtime
  handler     = var.handler
  memory_size = var.memory_size
  timeout     = var.timeout

  layers        = var.layers
  architectures = var.run_at_edge == false ? [var.architecture] : ["x86_64"]
  publish       = var.publish
  environment {
    variables = var.environment_variables
  }

  dynamic "tracing_config" {
    for_each = var.xray_tracing.enable == true ? [var.xray_tracing] : []
    content {
      mode = tracing_config.value.mode
    }
  }

  dynamic "vpc_config" {
    for_each = var.vpc != null ? [var.vpc] : []

    content {
      security_group_ids = vpc_config.value.security_group_ids
      subnet_ids         = vpc_config.value.subnet_ids
    }
  }

  timeouts {
    create = try(var.timeouts.create, null)
    update = try(var.timeouts.update, null)
    delete = try(var.timeouts.delete, null)
  }
}

resource "aws_lambda_alias" "lambda_alias" {
  for_each         = var.run_at_edge == false ? toset(local.alias_names) : []
  name             = each.value
  function_name    = aws_lambda_function.lambda_function.function_name
  function_version = aws_lambda_function.lambda_function.version

  lifecycle {
    ignore_changes = [
      function_version
    ]
  }
}
resource "terraform_data" "update_alias" {
  count            = var.run_at_edge == false && var.aliases.create ? 1 : 0
  triggers_replace = [aws_lambda_function.lambda_function.version, var.aliases.alias_to_update]

  provisioner "local-exec" {
    command = "/bin/bash ${path.module}/scripts/update-alias.sh"

    environment = {
      "FUNCTION_NAME"    = aws_lambda_function.lambda_function.function_name
      "FUNCTION_VERSION" = aws_lambda_function.lambda_function.version
      "FUNCTION_ALIAS"   = var.aliases.alias_to_update
    }
  }

  depends_on = [aws_lambda_alias.lambda_alias]
}

resource "aws_lambda_function_url" "function_url" {
  for_each = var.run_at_edge == false && var.function_url.create ? toset(local.alias_names) : []

  function_name      = aws_lambda_function.lambda_function.function_name
  qualifier          = aws_lambda_alias.lambda_alias[each.value].name
  authorization_type = var.function_url.authorization_type
  invoke_mode        = "BUFFERED"
}

resource "aws_lambda_permission" "function_url_permission" {
  count = var.run_at_edge == false && var.function_url.create ? 1 : 0

  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.lambda_function.function_name
  principal              = "*"
  function_url_auth_type = var.function_url.authorization_type
}

# Cloudwatch Logs

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  count = var.run_at_edge == false ? 1 : 0

  name              = "/aws/lambda/${local.prefix}${var.function_name}${local.suffix}"
  retention_in_days = var.cloudwatch_log.retention_in_days
}

# IAM

resource "aws_iam_role" "lambda_iam" {
  name                 = "${local.prefix}${var.function_name}-role${local.suffix}"
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

  provider = aws.iam
}

resource "aws_iam_policy" "lambda_policy" {
  name = "${local.prefix}${var.function_name}-lambda-policy${local.suffix}"
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
      var.xray_tracing.enable ? [
        {
          "Action" : [
            "xray:PutTraceSegments",
            "xray:PutTelemetryRecords"
          ],
          "Resource" : "*",
          "Effect" : "Allow"
        }
      ] : [],
    var.iam_policy_statements)
  })

  provider = aws.iam
}

resource "aws_iam_role_policy_attachment" "policy_attachment" {
  role       = aws_iam_role.lambda_iam.name
  policy_arn = aws_iam_policy.lambda_policy.arn

  provider = aws.iam
}

resource "aws_iam_policy" "additional_policy" {
  for_each = {
    for additional_iam_policy in var.additional_iam_policies : additional_iam_policy.name => additional_iam_policy if additional_iam_policy.policy != null
  }
  name = "${local.prefix}${var.function_name}-${each.key}${local.suffix}"
  path = var.iam.path

  policy = each.value.policy

  provider = aws.iam
}

resource "aws_iam_role_policy_attachment" "additional_policy_attachment" {
  for_each = {
    for additional_iam_policy in var.additional_iam_policies : additional_iam_policy.name => additional_iam_policy
  }
  role       = aws_iam_role.lambda_iam.name
  policy_arn = coalesce(each.value.arn, aws_iam_policy.additional_policy[each.key].arn)

  provider = aws.iam
}

# Event Rule (CRON)

resource "aws_cloudwatch_event_rule" "cron" {
  count = local.trigger_on_schedule ? 1 : 0

  name                = "${local.prefix}${var.function_name}-cron${local.suffix}"
  schedule_expression = var.schedule
}

resource "aws_cloudwatch_event_target" "trigger_lambda_on_schedule" {
  count = local.trigger_on_schedule ? 1 : 0

  rule      = aws_cloudwatch_event_rule.cron[0].name
  target_id = "lambda"
  arn       = try(aws_lambda_alias.lambda_alias[0].arn, aws_lambda_function.lambda_function.arn)
}

resource "aws_lambda_permission" "allow_eventbridge_to_invoke_lambda" {
  count = local.trigger_on_schedule ? 1 : 0

  statement_id  = "AllowExecutionFromEventbridge"
  action        = "lambda:InvokeFunction"
  function_name = try(aws_lambda_alias.lambda_alias[local.alias_names[0]].function_name, aws_lambda_function.lambda_function.function_name)
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cron[0].arn
}
