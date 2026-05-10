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
  type    = list(string)
  default = []
}

variable "blob_data_reader_principal_ids" {
  type    = list(string)
  default = []
}

variable "log_analytics_workspace_id" {
  type    = string
  default = null
}

variable "tags" {
  type    = map(string)
  default = {}
}
