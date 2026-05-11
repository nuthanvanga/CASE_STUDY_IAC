###############################################################################
# Azure Container Registry (ACR)
# - Premium SKU for private endpoint, geo-replication, content trust, and
#   customer-managed key support.
# - Public network access disabled; access is via private endpoint only.
###############################################################################

resource "azurerm_container_registry" "this" {
  name                          = var.name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  sku                           = "Premium"
  admin_enabled                 = false
  public_network_access_enabled = false
  zone_redundancy_enabled       = true
  data_endpoint_enabled         = true
  tags                          = var.tags

  identity {
    type = "SystemAssigned"
  }

  retention_policy {
    enabled = true
    days    = 30
  }

  trust_policy {
    enabled = true
  }

  dynamic "georeplications" {
    for_each = var.geo_replication_locations
    content {
      location                = georeplications.value
      zone_redundancy_enabled = true
      tags                    = var.tags
    }
  }
}

###############################################################################
# Private Endpoint
###############################################################################
resource "azurerm_private_endpoint" "acr" {
  name                = "${var.name}-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "${var.name}-psc"
    private_connection_resource_id = azurerm_container_registry.this.id
    subresource_names              = ["registry"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "acr-dns"
    private_dns_zone_ids = [var.private_dns_zone_id]
  }
}

###############################################################################
# AcrPull role assignments (typically AKS kubelet identity)
###############################################################################
resource "azurerm_role_assignment" "acrpull" {
  for_each             = var.acrpull_principal_ids
  scope                = azurerm_container_registry.this.id
  role_definition_name = "AcrPull"
  principal_id         = each.value
}
