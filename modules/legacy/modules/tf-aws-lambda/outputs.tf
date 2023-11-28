output "function_name" {
  description = "The lambda function name"
  value       = aws_lambda_function.lambda_function.function_name
}

output "function_arn" {
  description = "The lambda ARN"
  value       = aws_lambda_function.lambda_function.arn
}

output "function_version" {
  description = "The function version that is deployed"
  value       = aws_lambda_function.lambda_function.version
}

output "invoke_arn" {
  description = "The API Gateway invoke ARN"
  value       = aws_lambda_function.lambda_function.invoke_arn
}

output "qualified_arn" {
  description = "The function qualified ARN"
  value       = aws_lambda_function.lambda_function.qualified_arn
}

output "function_url_hostname" {
  description = "The hostname for the lambda function url"
  value       = length(aws_lambda_function_url.function_url) > 0 ? trimsuffix(trimprefix(one(aws_lambda_function_url.function_url).function_url, "https://"), "/") : null
}
