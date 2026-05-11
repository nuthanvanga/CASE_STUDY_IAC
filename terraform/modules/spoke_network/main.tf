###############################################################################
# Spoke VNet (workload network for AKS, App Service, Key Vault, Storage, ACR)
#
# - All workload resources land in this VNet via dedicated subnets.
# - Subnets:
#     snet-aks       : AKS node pools (overlay pod CIDR, so /22 host subnet)
#     snet-appsvc    : delegated to Microsoft.Web/serverFarms for App Service
#                      regional VNet integration
#     snet-pe        : private endpoints for KV, Storage, ACR, App Service
#     snet-appgw     : reserved for Application Gateway / ingress
# - NSGs on AKS and PE subnets.
# - NAT Gateway gives AKS predictable, zone-redundant outbound egress.
# - Bidirectional VNet peering with the hub.
# - All hub Private DNS zones are linked to this spoke so private endpoints
#   created here resolve correctly from anywhere in the topology.
###############################################################################

resource "azurerm_virtual_network" "spoke" {
  name                = "${var.name_prefix}-${var.spoke_name}-vnet"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.vnet_address_space
  tags                = var.tags
}

###############################################################################
# Subnet CIDRs - derived from vnet_address_space[0] when not explicitly set.
# Keeps each env's subnet plan in sync with whatever address space it picks.
###############################################################################
locals {
  vnet_prefix = var.vnet_address_space[0]

  aks_cidr    = coalesce(var.aks_subnet_cidr, cidrsubnet(local.vnet_prefix, 6, 0))
  appsvc_cidr = coalesce(var.appsvc_subnet_cidr, cidrsubnet(local.vnet_prefix, 8, 4))
  pe_cidr     = coalesce(var.pe_subnet_cidr, cidrsubnet(local.vnet_prefix, 8, 5))
  appgw_cidr  = coalesce(var.appgw_subnet_cidr, cidrsubnet(local.vnet_prefix, 8, 6))
}

###############################################################################
# Workload subnets
###############################################################################
resource "azurerm_subnet" "aks" {
  name                 = "snet-aks"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = [local.aks_cidr]
  service_endpoints    = ["Microsoft.KeyVault", "Microsoft.ContainerRegistry", "Microsoft.Storage"]
}

resource "azurerm_subnet" "appsvc" {
  name                 = "snet-appsvc"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = [local.appsvc_cidr]

  delegation {
    name = "appservice-delegation"
    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

resource "azurerm_subnet" "pe" {
  name                 = "snet-private-endpoints"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = [local.pe_cidr]

  private_endpoint_network_policies_enabled = false
}

resource "azurerm_subnet" "appgw" {
  name                 = "snet-appgw"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = [local.appgw_cidr]
}

###############################################################################
# Network Security Groups
###############################################################################
resource "azurerm_network_security_group" "aks" {
  name                = "${var.name_prefix}-${var.spoke_name}-nsg-aks"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  security_rule {
    name                       = "AllowAzureLoadBalancerInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowVNetInbound"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "aks" {
  subnet_id                 = azurerm_subnet.aks.id
  network_security_group_id = azurerm_network_security_group.aks.id
}

resource "azurerm_network_security_group" "pe" {
  name                = "${var.name_prefix}-${var.spoke_name}-nsg-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  security_rule {
    name                       = "AllowVNetInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "pe" {
  subnet_id                 = azurerm_subnet.pe.id
  network_security_group_id = azurerm_network_security_group.pe.id
}

###############################################################################
# NAT Gateway for stable outbound egress (recommended for production AKS)
###############################################################################
resource "azurerm_public_ip" "nat" {
  count               = var.enable_nat_gateway ? 1 : 0
  name                = "${var.name_prefix}-${var.spoke_name}-pip-nat"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
  tags                = var.tags
}

resource "azurerm_nat_gateway" "this" {
  count                   = var.enable_nat_gateway ? 1 : 0
  name                    = "${var.name_prefix}-${var.spoke_name}-natgw"
  location                = var.location
  resource_group_name     = var.resource_group_name
  sku_name                = "Standard"
  idle_timeout_in_minutes = 10
  tags                    = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "this" {
  count                = var.enable_nat_gateway ? 1 : 0
  nat_gateway_id       = azurerm_nat_gateway.this[0].id
  public_ip_address_id = azurerm_public_ip.nat[0].id
}

resource "azurerm_subnet_nat_gateway_association" "aks" {
  count          = var.enable_nat_gateway ? 1 : 0
  subnet_id      = azurerm_subnet.aks.id
  nat_gateway_id = azurerm_nat_gateway.this[0].id
}

###############################################################################
# VNet peering (bidirectional) with the hub.
#
# allow_forwarded_traffic = true on the spoke side lets traffic leave the spoke
# via a hub NVA / firewall in the future without re-peering.
###############################################################################
resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                         = "peer-${var.spoke_name}-to-hub"
  resource_group_name          = var.resource_group_name
  virtual_network_name         = azurerm_virtual_network.spoke.name
  remote_virtual_network_id    = var.hub_vnet_id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = var.use_hub_gateway
}

resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  name                         = "peer-hub-to-${var.spoke_name}"
  resource_group_name          = var.hub_resource_group_name
  virtual_network_name         = var.hub_vnet_name
  remote_virtual_network_id    = azurerm_virtual_network.spoke.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = var.hub_has_gateway
  use_remote_gateways          = false
}

###############################################################################
# Link every hub Private DNS zone to this spoke VNet so private endpoints
# created in the spoke are resolvable from the spoke and the hub.
###############################################################################
resource "azurerm_private_dns_zone_virtual_network_link" "spoke" {
  for_each              = var.hub_private_dns_zone_names
  name                  = "${var.spoke_name}-${each.key}-link"
  resource_group_name   = var.hub_resource_group_name
  private_dns_zone_name = each.value
  virtual_network_id    = azurerm_virtual_network.spoke.id
  registration_enabled  = false
  tags                  = var.tags
}
