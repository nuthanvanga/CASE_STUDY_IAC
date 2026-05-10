###############################################################################
# Hub VNet (hub-and-spoke topology)
# - Centralised egress, shared services and Private DNS zones live here.
# - All workload resources (AKS, App Service, Key Vault, Storage, ACR, ...)
#   live in spoke VNets and reach this hub via VNet peering.
# - Reserved subnets created up-front so a Bastion / Firewall / VPN gateway
#   can be added without re-cidr'ing later.
###############################################################################

resource "azurerm_virtual_network" "hub" {
  name                = "${var.name_prefix}-hub-vnet"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.vnet_address_space
  tags                = var.tags
}

# GatewaySubnet - reserved for ExpressRoute / VPN Gateway. Name is fixed by Azure.
resource "azurerm_subnet" "gateway" {
  count                = var.create_gateway_subnet ? 1 : 0
  name                 = "GatewaySubnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.gateway_subnet_cidr]
}

# AzureFirewallSubnet - reserved for Azure Firewall. Name is fixed by Azure.
resource "azurerm_subnet" "firewall" {
  count                = var.create_firewall_subnet ? 1 : 0
  name                 = "AzureFirewallSubnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.firewall_subnet_cidr]
}

# AzureBastionSubnet - reserved for Azure Bastion. Name is fixed by Azure.
resource "azurerm_subnet" "bastion" {
  count                = var.create_bastion_subnet ? 1 : 0
  name                 = "AzureBastionSubnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.bastion_subnet_cidr]
}

# Shared-services subnet (jumpboxes, DNS resolvers, monitoring relays, etc.)
resource "azurerm_subnet" "shared" {
  name                 = "snet-shared"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.shared_subnet_cidr]
}

###############################################################################
# Central Private DNS zones for private endpoints.
# Living in the hub means every spoke and the hub itself resolve to the
# same private IPs - this is the canonical hub-and-spoke pattern.
###############################################################################
locals {
  private_dns_zone_names = {
    keyvault       = "privatelink.vaultcore.azure.net"
    acr            = "privatelink.azurecr.io"
    blob           = "privatelink.blob.core.windows.net"
    file           = "privatelink.file.core.windows.net"
    queue          = "privatelink.queue.core.windows.net"
    table          = "privatelink.table.core.windows.net"
    dfs            = "privatelink.dfs.core.windows.net"
    appservice     = "privatelink.azurewebsites.net"
    appservice_scm = "privatelink.scm.azurewebsites.net"
  }
}

resource "azurerm_private_dns_zone" "this" {
  for_each            = local.private_dns_zone_names
  name                = each.value
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# Link each zone to the hub itself so hub workloads (jumpboxes, agents) can resolve PEs.
resource "azurerm_private_dns_zone_virtual_network_link" "hub" {
  for_each              = azurerm_private_dns_zone.this
  name                  = "hub-${each.key}-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = each.value.name
  virtual_network_id    = azurerm_virtual_network.hub.id
  registration_enabled  = false
  tags                  = var.tags
}
