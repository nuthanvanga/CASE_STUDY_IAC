###############################################################################
# Required - no defaults, must come from a tfvars file
###############################################################################
variable "subscription_id" {
  type        = string
  description = "Target Azure subscription id."
}

variable "tenant_id" {
  type        = string
  description = "AAD tenant id."
}

variable "environment" {
  type        = string
  description = "Logical environment name (dev / staging / prod). Used in tags only."
}

variable "name_prefix" {
  type        = string
  description = "Short prefix for resource names. e.g. dev-uaen, stg-uaen, prod-uaen."
}

###############################################################################
# Region
###############################################################################
variable "location" {
  type    = string
  default = "uaenorth"
}

variable "tags" {
  type = map(string)
  default = {
    managed_by = "terraform"
  }
}

###############################################################################
# Hub-and-spoke addressing
###############################################################################
variable "hub_vnet_address_space" {
  type        = list(string)
  description = "Hub VNet CIDR(s). Must not overlap other envs or on-prem."
}

variable "spoke_vnet_address_space" {
  type        = list(string)
  description = "Spoke VNet CIDR(s). Must not overlap other envs or on-prem."
}

###############################################################################
# AKS / KV / ACR
###############################################################################
variable "aks_admin_group_object_ids" {
  type        = list(string)
  default     = []
  description = "AAD group object ids that get cluster-admin via Azure RBAC."
}

variable "kv_admin_principal_ids" {
  type        = list(string)
  default     = []
  description = "Object ids that get Key Vault Administrator (e.g. CI/CD service principal)."
}

variable "acr_geo_replication_locations" {
  type    = list(string)
  default = []
}

###############################################################################
# App Service
###############################################################################
variable "appsvc_app_name" {
  type = string
}

variable "appsvc_plan_sku" {
  type    = string
  default = "B1"
}

variable "appsvc_zone_redundant" {
  type    = bool
  default = false
}

variable "appsvc_worker_count" {
  type    = number
  default = 1
}

###############################################################################
# Log Analytics sizing
###############################################################################
variable "log_retention_days" {
  type    = number
  default = 30
}

variable "log_daily_quota_gb" {
  type    = number
  default = 5
}

###############################################################################
# Storage subresources to expose via private endpoint (blob is always on)
###############################################################################
variable "storage_enable_file_endpoint" {
  type    = bool
  default = false
}

variable "storage_enable_queue_endpoint" {
  type    = bool
  default = false
}

variable "storage_enable_table_endpoint" {
  type    = bool
  default = false
}

variable "storage_enable_dfs_endpoint" {
  type    = bool
  default = false
}

###############################################################################
# Alerting
###############################################################################
variable "alert_email_receivers" {
  type        = list(string)
  default     = []
  description = "Email addresses to receive Azure Monitor alerts."
}
