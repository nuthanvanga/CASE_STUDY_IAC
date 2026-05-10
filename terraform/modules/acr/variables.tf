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

variable "aks_kubelet_object_id" {
  type        = string
  default     = null
  description = "Object id of the AKS kubelet identity. AcrPull is granted when provided."
}

variable "tags" {
  type    = map(string)
  default = {}
}
