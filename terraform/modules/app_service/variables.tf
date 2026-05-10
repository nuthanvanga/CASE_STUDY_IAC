variable "app_name" {
  type        = string
  description = "Globally unique App Service name."
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "appsvc_subnet_id" {
  type = string
}

variable "plan_sku" {
  type        = string
  default     = "P1v3"
  description = "Plan SKU. Use P*v3 for production (PremiumV3)."
}

variable "worker_count" {
  type    = number
  default = 3
}

variable "zone_redundant" {
  type    = bool
  default = true
}

variable "public_network_access_enabled" {
  type        = bool
  default     = true
  description = "Set to false to fully lock down to private endpoint only."
}

variable "health_check_path" {
  type    = string
  default = "/health"
}

variable "app_settings" {
  type    = map(string)
  default = {}
}

variable "allowed_ip_rules" {
  type = list(object({
    name     = string
    cidr     = string
    priority = number
  }))
  default = []
}

variable "create_staging_slot" {
  type    = bool
  default = true
}

variable "log_analytics_workspace_id" {
  type    = string
  default = null
}

variable "tags" {
  type    = map(string)
  default = {}
}
