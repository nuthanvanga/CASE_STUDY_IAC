output "vnet_id" {
  value       = azurerm_virtual_network.hub.id
  description = "Resource ID of the hub VNet."
}

output "vnet_name" {
  value = azurerm_virtual_network.hub.name
}

output "resource_group_name" {
  value = var.resource_group_name
}

output "gateway_subnet_id" {
  value = try(azurerm_subnet.gateway[0].id, null)
}

output "firewall_subnet_id" {
  value = try(azurerm_subnet.firewall[0].id, null)
}

output "bastion_subnet_id" {
  value = try(azurerm_subnet.bastion[0].id, null)
}

output "shared_subnet_id" {
  value = azurerm_subnet.shared.id
}

# Convenience outputs for individual private DNS zone IDs (consumed by spoke
# private endpoints).
output "private_dns_zone_ids" {
  description = "Map of logical name -> Private DNS zone resource ID."
  value       = { for k, v in azurerm_private_dns_zone.this : k => v.id }
}

output "private_dns_zone_names" {
  description = "Map of logical name -> Private DNS zone FQDN."
  value       = { for k, v in azurerm_private_dns_zone.this : k => v.name }
}
