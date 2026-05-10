###############################################################################
# Azure Storage Account
# - StorageV2, ZRS, TLS1.2+, no shared key access (AAD only), no public network.
# - Private endpoint(s) live in the spoke private-endpoint subnet.
# - DNS resolution flows through the hub-hosted Private DNS zones.
###############################################################################

resource "azurerm_storage_account" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = var.replication_type
  access_tier              = "Hot"

  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  shared_access_key_enabled       = var.shared_access_key_enabled
  public_network_access_enabled   = false
  allow_nested_items_to_be_public = false
  default_to_oauth_authentication = true

  blob_properties {
    versioning_enabled       = true
    change_feed_enabled      = true
    last_access_time_enabled = true

    delete_retention_policy {
      days = 30
    }
    container_delete_retention_policy {
      days = 30
    }
  }

  network_rules {
    default_action             = "Deny"
    bypass                     = ["AzureServices", "Logging", "Metrics"]
    ip_rules                   = var.allowed_ip_ranges
    virtual_network_subnet_ids = var.allowed_subnet_ids
  }

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

###############################################################################
# Private endpoints - one per enabled subresource (blob/file/queue/table/dfs)
###############################################################################
locals {
  # Map each enabled subresource to the matching Private DNS zone id.
  enabled_subresources = {
    for k, enabled in {
      blob  = var.enable_blob_endpoint
      file  = var.enable_file_endpoint
      queue = var.enable_queue_endpoint
      table = var.enable_table_endpoint
      dfs   = var.enable_dfs_endpoint
    } : k => enabled if enabled
  }
}

resource "azurerm_private_endpoint" "this" {
  for_each            = local.enabled_subresources
  name                = "${var.name}-${each.key}-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "${var.name}-${each.key}-psc"
    private_connection_resource_id = azurerm_storage_account.this.id
    subresource_names              = [each.key]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "${each.key}-dns"
    private_dns_zone_ids = [var.private_dns_zone_ids[each.key]]
  }
}

###############################################################################
# Optional Storage Blob Data Contributor / Reader assignments for workloads
###############################################################################
resource "azurerm_role_assignment" "blob_contributor" {
  count                = length(var.blob_data_contributor_principal_ids)
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.blob_data_contributor_principal_ids[count.index]
}

resource "azurerm_role_assignment" "blob_reader" {
  count                = length(var.blob_data_reader_principal_ids)
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = var.blob_data_reader_principal_ids[count.index]
}

###############################################################################
# Diagnostic settings
###############################################################################
resource "azurerm_monitor_diagnostic_setting" "account" {
  count                      = var.log_analytics_workspace_id == null ? 0 : 1
  name                       = "${var.name}-diag"
  target_resource_id         = azurerm_storage_account.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  metric {
    category = "Transaction"
    enabled  = true
  }
  metric {
    category = "Capacity"
    enabled  = true
  }
}
