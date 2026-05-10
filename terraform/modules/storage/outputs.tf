output "id" {
  value = azurerm_storage_account.this.id
}

output "name" {
  value = azurerm_storage_account.this.name
}

output "primary_blob_endpoint" {
  value = azurerm_storage_account.this.primary_blob_endpoint
}

output "primary_dfs_endpoint" {
  value = azurerm_storage_account.this.primary_dfs_endpoint
}

output "principal_id" {
  value = try(azurerm_storage_account.this.identity[0].principal_id, null)
}

output "private_endpoint_ids" {
  value = { for k, v in azurerm_private_endpoint.this : k => v.id }
}
