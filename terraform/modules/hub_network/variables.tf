variable "name_prefix" {
  type        = string
  description = "Prefix used to name hub resources, e.g. 'prod-uaen'."
}

variable "location" {
  type        = string
  description = "Azure region for the hub VNet."
}

variable "resource_group_name" {
  type        = string
  description = "Resource group hosting the hub networking + Private DNS zones."
}

variable "vnet_address_space" {
  type        = list(string)
  default     = ["10.10.0.0/16"]
  description = "Hub VNet CIDR. Must NOT overlap any spoke."
}

variable "gateway_subnet_cidr" {
  type        = string
  default     = "10.10.0.0/27"
  description = "CIDR for the GatewaySubnet (ExpressRoute / VPN)."
}

variable "create_gateway_subnet" {
  type    = bool
  default = true
}

variable "firewall_subnet_cidr" {
  type        = string
  default     = "10.10.1.0/26"
  description = "CIDR for AzureFirewallSubnet."
}

variable "create_firewall_subnet" {
  type    = bool
  default = false
}

variable "bastion_subnet_cidr" {
  type        = string
  default     = "10.10.2.0/26"
  description = "CIDR for AzureBastionSubnet (must be /26 or larger)."
}

variable "create_bastion_subnet" {
  type    = bool
  default = true
}

variable "shared_subnet_cidr" {
  type        = string
  default     = "10.10.3.0/24"
  description = "CIDR for shared services (jumpbox, DNS resolver, monitoring agents)."
}

variable "tags" {
  type    = map(string)
  default = {}
}
