variable "name" {
  type        = string
  description = "Globally unique ACR name (lowercase alphanumerics)."
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "private_endpoint_subnet_id" {
  type        = string
  description = "Subnet to host the ACR private endpoint."
}

variable "private_dns_zone_id" {
  type        = string
  description = "Private DNS zone id for privatelink.azurecr.io."
}

variable "geo_replication_locations" {
  type        = list(string)
  default     = []
  description = "Optional list of secondary regions for geo-replication (e.g. ['uaecentral'])."
}

variable "acrpull_principal_ids" {
  type        = map(string)
  default     = {}
  description = <<-EOT
    Map of stable key (e.g. "aks_kubelet") -> principal object id that
    should receive AcrPull on this registry. Map (not list) so for_each
    keys are known at plan time even when the principal ids are computed
    from other modules.
  EOT
}

variable "tags" {
  type    = map(string)
  default = {}
}
