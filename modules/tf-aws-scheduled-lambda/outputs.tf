output "function_name" {
  description = "The lambda function name"
  value       = module.function.function_name
}

output "function_arn" {
  description = "The lambda ARN"
  value       = module.function.function_arn
}

output "function_version" {
  description = "The function version that is deployed"
  value       = module.function.function_version
}

output "function_url_hostname" {
  description = "The hostname for the lambda function url"
  value       = module.function.function_url_hostname
}
