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

###############################################################################
# Subnet CIDRs - leave null to auto-derive from vnet_address_space[0] using
# cidrsubnet(). For a /16 hub the derived layout is:
#   GatewaySubnet       /27  at offset 0   (e.g. 10.10.0.0/27)
#   AzureFirewallSubnet /26  at offset 64  (10.10.1.0/26)
#   AzureBastionSubnet  /26  at offset 128 (10.10.2.0/26)
#   snet-shared         /24  at offset 768 (10.10.3.0/24)
# Override per-subnet only if you need a non-standard layout.
###############################################################################
variable "gateway_subnet_cidr" {
  type        = string
  default     = null
  description = "CIDR for the GatewaySubnet (ExpressRoute / VPN). Defaults to first /27 of the hub VNet."
}

variable "create_gateway_subnet" {
  type    = bool
  default = true
}

variable "firewall_subnet_cidr" {
  type        = string
  default     = null
  description = "CIDR for AzureFirewallSubnet."
}

variable "create_firewall_subnet" {
  type    = bool
  default = false
}

variable "bastion_subnet_cidr" {
  type        = string
  default     = null
  description = "CIDR for AzureBastionSubnet (must be /26 or larger)."
}

variable "create_bastion_subnet" {
  type    = bool
  default = true
}

variable "shared_subnet_cidr" {
  type        = string
  default     = null
  description = "CIDR for shared services (jumpbox, DNS resolver, monitoring agents)."
}

variable "tags" {
  type    = map(string)
  default = {}
}
