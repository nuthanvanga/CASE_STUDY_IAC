###############################################################################
# Required - no defaults. CI supplies these via TF_VAR_subscription_id /
# TF_VAR_tenant_id env vars on the terraform plan task.
###############################################################################
variable "subscription_id" {
  type        = string
  description = "Target Azure subscription id."
}

variable "tenant_id" {
  type        = string
  description = "AAD tenant id."
}

###############################################################################
# Naming + region (env-specific defaults baked in)
###############################################################################
variable "location" {
  type    = string
  default = "uaenorth"
}

variable "name_prefix" {
  type    = string
  default = "stg-uaen"
}

variable "tags" {
  type = map(string)
  default = {
    environment = "staging"
    region      = "uae-north"
    owner       = "platform-team"
    cost_center = "eng-platform"
    managed_by  = "terraform"
  }
}

###############################################################################
# Hub-and-spoke addressing
###############################################################################
variable "hub_vnet_address_space" {
  type    = list(string)
  default = ["10.50.0.0/16"]
}

variable "spoke_vnet_address_space" {
  type    = list(string)
  default = ["10.60.0.0/16"]
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
  type    = string
  default = "stg-uaen-app-api"
}

variable "appsvc_plan_sku" {
  type    = string
  default = "S1"
}

variable "appsvc_zone_redundant" {
  type    = bool
  default = false
}

variable "appsvc_worker_count" {
  type    = number
  default = 2
}

###############################################################################
# Log Analytics sizing
###############################################################################
variable "log_retention_days" {
  type    = number
  default = 60
}

variable "log_daily_quota_gb" {
  type    = number
  default = 20
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
