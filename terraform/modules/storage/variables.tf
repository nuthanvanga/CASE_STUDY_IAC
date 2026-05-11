variable "name" {
  type        = string
  description = "Globally unique storage account name (3-24 chars, lowercase letters and digits)."
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "replication_type" {
  type        = string
  default     = "ZRS"
  description = "Replication: LRS / ZRS / GRS / RAGRS / GZRS / RAGZRS."
}

variable "shared_access_key_enabled" {
  type        = bool
  default     = false
  description = "Disable shared keys; force Entra ID auth (recommended)."
}

variable "private_endpoint_subnet_id" {
  type        = string
  description = "Subnet (in the spoke) that hosts the storage private endpoints."
}

variable "private_dns_zone_ids" {
  type        = map(string)
  description = "Map of subresource name (blob/file/queue/table/dfs) -> Private DNS zone ID."
}

variable "enable_blob_endpoint" {
  type    = bool
  default = true
}

variable "enable_file_endpoint" {
  type    = bool
  default = false
}

variable "enable_queue_endpoint" {
  type    = bool
  default = false
}

variable "enable_table_endpoint" {
  type    = bool
  default = false
}

variable "enable_dfs_endpoint" {
  type    = bool
  default = false
}

variable "allowed_ip_ranges" {
  type    = list(string)
  default = []
}

variable "allowed_subnet_ids" {
  type    = list(string)
  default = []
}

variable "blob_data_contributor_principal_ids" {
  type        = map(string)
  default     = {}
  description = <<-EOT
    Map of stable key (e.g. "appservice") -> principal object id.
    Map (not list) so for_each keys are known at plan time even when the
    principal ids are computed from other modules.
  EOT
}

variable "blob_data_reader_principal_ids" {
  type        = map(string)
  default     = {}
  description = "Map of stable key -> principal object id for Storage Blob Data Reader."
}

variable "log_analytics_workspace_id" {
  type    = string
  default = null
}

variable "enable_diagnostics" {
  type        = bool
  default     = true
  description = <<-EOT
    Whether to create the diagnostic setting that ships logs/metrics to
    Log Analytics. Gated by an explicit boolean (rather than a null check
    on log_analytics_workspace_id) so the count is known at plan time even
    when the workspace id is computed.
  EOT
}

variable "tags" {
  type    = map(string)
  default = {}
}
