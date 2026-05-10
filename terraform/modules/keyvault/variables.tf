variable "name" {
  type        = string
  description = "Globally unique Key Vault name (3-24 chars, alphanumerics and dashes)."
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "private_endpoint_subnet_id" {
  type = string
}

variable "private_dns_zone_id" {
  type = string
}

variable "kv_admin_principal_ids" {
  type        = list(string)
  default     = []
  description = "Principal object IDs that should receive Key Vault Administrator (e.g. CI SP)."
}

variable "kv_secret_user_principal_ids" {
  type        = list(string)
  default     = []
  description = "Workload identities that should receive Key Vault Secrets User."
}

variable "allowed_ip_ranges" {
  type        = list(string)
  default     = []
  description = "Optional list of public IP CIDR ranges allowed to bypass the private endpoint."
}

variable "allowed_subnet_ids" {
  type    = list(string)
  default = []
}

variable "tags" {
  type    = map(string)
  default = {}
}
