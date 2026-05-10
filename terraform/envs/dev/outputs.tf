output "resource_group_core" {
  value = azurerm_resource_group.core.name
}

output "resource_group_hub" {
  value = azurerm_resource_group.hub.name
}

output "resource_group_spoke" {
  value = azurerm_resource_group.spoke.name
}

output "resource_group_platform" {
  value = azurerm_resource_group.platform.name
}

output "hub_vnet_id" {
  value = module.hub_network.vnet_id
}

output "spoke_vnet_id" {
  value = module.spoke_network.vnet_id
}

output "private_dns_zone_ids" {
  value = module.hub_network.private_dns_zone_ids
}

output "aks_id" {
  value = module.aks.id
}

output "aks_name" {
  value = module.aks.name
}

output "aks_oidc_issuer_url" {
  value = module.aks.oidc_issuer_url
}

output "acr_login_server" {
  value = module.acr.login_server
}

output "key_vault_uri" {
  value = module.keyvault.vault_uri
}

output "app_service_hostname" {
  value = module.appservice.default_hostname
}

output "storage_account_name" {
  value = module.storage.name
}

output "storage_blob_endpoint" {
  value = module.storage.primary_blob_endpoint
}

output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.this.id
}
