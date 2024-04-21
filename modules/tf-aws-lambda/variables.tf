variable "prefix" {
  description = "A prefix which will be attached to resource name to esnure resources are random"
  type        = string
}

variable "suffix" {
  description = "A suffix which will be attached to resource name to esnure resources are random"
  type        = string
}

variable "function_name" {
  description = "The name of the lambda function"
  type        = string
}

variable "function_code" {
  type = object({
    zip = optional(object({
      path = string
      hash = string
    }))
    s3 = optional(object({
      bucket         = string
      key            = string
      object_version = optional(string)
    }))
  })
}

variable "runtime" {
  description = "The runtime of the lambda function"
  type        = string
}

variable "handler" {
  description = "The handler of the lambda function"
  type        = string
}

variable "memory_size" {
  description = "The memory size of the lambda function"
  type        = number
}

variable "timeout" {
  description = "The timeout of the lambda function"
  type        = number
}

variable "iam" {
  description = "Override the default IAM configuration"
  type = object({
    path                 = optional(string, "/")
    permissions_boundary = optional(string)
  })
  default = {}
}

variable "cloudwatch_log" {
  description = "Override the Cloudwatch logs configuration"
  type = object({
    retention_in_days = number
  })
  default = {
    retention_in_days = 7
  }
}

variable "environment_variables" {
  description = "Specify environment variables for the lambda function"
  type        = map(string)
  default     = {}
}

variable "iam_policy_statements" {
  description = "Additional IAM policy statements to attach to the role in addition to the default cloudwatch logs, xray and kms permissions"
  type        = any
  default     = []
}

variable "additional_iam_policies" {
  description = "Specify additional IAM policies to attach to the lambda execution role"
  type = list(object({
    name   = string,
    arn    = optional(string)
    policy = optional(string)
  }))
  default = []

  validation {
    condition = alltrue([
      for additional_iam_policy in var.additional_iam_policies : additional_iam_policy.arn != null || additional_iam_policy.policy != null
    ])
    error_message = "Either the ARN or policy must be specified for each additional IAM policy"
  }
}

variable "vpc" {
  description = "The configuration to run the lambda in a VPC"
  type = object({
    security_group_ids = list(string),
    subnet_ids         = list(string)
  })
  default = null
}

variable "publish" {
  description = "Whether to publish a new lambda version"
  type        = bool
  default     = true
}

variable "function_url" {
  description = "Configure function URL"
  type = object({
    create              = optional(bool, true)
    allow_any_principal = optional(bool, false)
    authorization_type  = optional(string, "NONE")
    enable_streaming    = optional(bool, false)
  })
  default = {}
}

variable "architecture" {
  description = "Instruction set architecture for the lambda function"
  type        = string
}

variable "run_at_edge" {
  description = "Whether the function runs at the edge"
  type        = bool
  default     = false
}

variable "aliases" {
  description = "List of aliases to create"
  type = object({
    create          = optional(bool, true)
    names           = optional(list(string), ["stable"])
    alias_to_update = optional(string, "stable")
  })
  default = {}
}

variable "xray_tracing" {
  description = "Configuration for AWS tracing on the function"
  type = object({
    enable = optional(bool, false),
    mode   = optional(string, "Active")
  })
  default = {}
}

variable "layers" {
  description = "A list of layer arns to associate with the lambda"
  type        = list(string)
  default     = null
}

variable "timeouts" {
  description = "Define maximum timeout for creating, updating, and deleting function"
  type = object({
    create = optional(string)
    update = optional(string)
    delete = optional(string)
  })
  default = {}
}

variable "schedule" {
  description = "The schedule to invoke the function"
  type        = string
  default     = null
}

variable "scripts" {
  description = "Modify default script behaviours"
  type = object({
    interpreter                      = optional(string)
    additional_environment_variables = optional(map(string))
    update_alias_script = optional(object({
      interpreter                      = optional(string)
      path                             = optional(string)
      additional_environment_variables = optional(map(string))
    }))
  })
  default = {}
}
