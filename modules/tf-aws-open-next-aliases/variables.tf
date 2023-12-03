variable "prefix" {
  description = "A prefix which will be attached to the resource name to ensure resources are random"
  type        = string
  default     = null
}

variable "suffix" {
  description = "A suffix which will be attached to the resource name to ensure resources are random"
  type        = string
  default     = null
}

variable "use_continuous_deployment" {
  description = "Whether continuous deployment is used"
  type        = bool
}

variable "continuous_deployment_strategy" {
  description = "The continuous deployment strategy"
  type        = string
}