output "name" {
  description = "The lambda function name"
  value       = aws_lambda_function.lambda_function.function_name
}

output "arn" {
  description = "The lambda ARN"
  value       = aws_lambda_function.lambda_function.arn
}

output "version" {
  description = "The function version that is deployed"
  value       = aws_lambda_function.lambda_function.version
}

output "qualified_arn" {
  description = "The function qualified ARN"
  value       = aws_lambda_function.lambda_function.qualified_arn
}

output "url_hostnames" {
  description = "The hostname for the lambda function urls"
  value       = length(aws_lambda_function_url.function_url) > 0 ? { for url in aws_lambda_function_url.function_url : url.qualifier => trimsuffix(trimprefix(aws_lambda_function_url.function_url[url.qualifier].function_url, "https://"), "/") } : {}
}
