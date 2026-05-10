###############################################################################
# Azure Key Vault
# - Premium SKU (HSM-backed keys), purge protection + soft delete on.
# - RBAC authorization model (no access policies).
# - Public network access disabled; access via private endpoint only.
###############################################################################

data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "this" {
  name                          = var.name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "premium"
  enabled_for_disk_encryption   = true
  enabled_for_template_deployment = true
  enable_rbac_authorization     = true
  purge_protection_enabled      = true
  soft_delete_retention_days    = 90
  public_network_access_enabled = false
  tags                          = var.tags

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
    ip_rules       = var.allowed_ip_ranges
    virtual_network_subnet_ids = var.allowed_subnet_ids
  }
}

###############################################################################
# Private endpoint for Key Vault
###############################################################################
resource "azurerm_private_endpoint" "kv" {
  name                = "${var.name}-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "${var.name}-psc"
    private_connection_resource_id = azurerm_key_vault.this.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "kv-dns"
    private_dns_zone_ids = [var.private_dns_zone_id]
  }
}

###############################################################################
# RBAC role assignments
###############################################################################
# Deployer (e.g. CI service principal) needs Key Vault Administrator
resource "azurerm_role_assignment" "deployer_admin" {
  count                = length(var.kv_admin_principal_ids)
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = var.kv_admin_principal_ids[count.index]
}

# Workloads (AKS/AppService) get Key Vault Secrets User
resource "azurerm_role_assignment" "secrets_user" {
  count                = length(var.kv_secret_user_principal_ids)
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = var.kv_secret_user_principal_ids[count.index]
}
