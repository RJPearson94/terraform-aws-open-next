# Lambda Function

module "function" {
  source = "../tf-aws-lambda"

  function_name = var.function_name
  zip_file      = var.zip_file
  hash          = var.hash

  runtime = var.runtime
  handler = var.handler

  memory_size = var.memory_size
  timeout     = var.timeout

  environment_variables = var.environment_variables

  additional_iam_policies = var.additional_iam_policies
  iam_policy_statements   = var.iam_policy_statements

  architecture = var.architecture

  iam            = var.iam
  cloudwatch_log = var.cloudwatch_log

  vpc = var.vpc

  prefix = var.prefix
  suffix = var.suffix

  providers = {
    aws.iam = aws.iam
  }
}

# Eventbridge

resource "aws_cloudwatch_event_rule" "cron" {
  name                = "${var.prefix}${var.function_name}-cron${var.suffix}"
  schedule_expression = var.schedule
}

resource "aws_cloudwatch_event_target" "trigger_lambda_on_schedule" {
  rule      = aws_cloudwatch_event_rule.cron.name
  target_id = "lambda"
  arn       = module.function.function_arn
}

resource "aws_lambda_permission" "allow_eventbridge_to_invoke_lambda" {
  statement_id  = "AllowExecutionFromEventbridge"
  action        = "lambda:InvokeFunction"
  function_name = module.function.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cron.arn
}
