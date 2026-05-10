variable "name_prefix" {
  type        = string
  description = "Prefix used to name spoke resources, e.g. 'prod-uaen'."
}

variable "spoke_name" {
  type        = string
  default     = "spoke"
  description = "Logical name of this spoke (used in resource names and peering names)."
}

variable "location" {
  type        = string
  description = "Azure region for the spoke VNet."
}

variable "resource_group_name" {
  type        = string
  description = "Resource group hosting spoke networking."
}

variable "vnet_address_space" {
  type        = list(string)
  default     = ["10.20.0.0/16"]
  description = "Spoke VNet CIDR. Must NOT overlap the hub or any other spoke."
}

variable "aks_subnet_cidr" {
  type    = string
  default = "10.20.0.0/22"
}

variable "appsvc_subnet_cidr" {
  type    = string
  default = "10.20.4.0/24"
}

variable "pe_subnet_cidr" {
  type    = string
  default = "10.20.5.0/24"
}

variable "appgw_subnet_cidr" {
  type    = string
  default = "10.20.6.0/24"
}

variable "enable_nat_gateway" {
  type        = bool
  default     = true
  description = "Whether to deploy a zone-redundant NAT Gateway for AKS egress."
}

###############################################################################
# Hub linkage
###############################################################################
variable "hub_vnet_id" {
  type        = string
  description = "Resource ID of the hub VNet to peer with."
}

variable "hub_vnet_name" {
  type        = string
  description = "Name of the hub VNet (needed for the reverse peering)."
}

variable "hub_resource_group_name" {
  type        = string
  description = "Resource group of the hub VNet (needed for the reverse peering and DNS zone links)."
}

variable "hub_private_dns_zone_names" {
  type        = map(string)
  default     = {}
  description = "Map of logical name -> Private DNS zone FQDN to link to this spoke."
}

variable "hub_has_gateway" {
  type        = bool
  default     = false
  description = "Set true if the hub has a VPN/ExpressRoute gateway whose transit should be allowed to spokes."
}

variable "use_hub_gateway" {
  type        = bool
  default     = false
  description = "Set true if this spoke should route on-prem traffic through the hub gateway."
}

variable "tags" {
  type    = map(string)
  default = {}
}
