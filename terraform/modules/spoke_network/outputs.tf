output "vnet_id" {
  value = azurerm_virtual_network.spoke.id
}

output "vnet_name" {
  value = azurerm_virtual_network.spoke.name
}

output "aks_subnet_id" {
  value = azurerm_subnet.aks.id
}

output "appsvc_subnet_id" {
  value = azurerm_subnet.appsvc.id
}

output "pe_subnet_id" {
  value = azurerm_subnet.pe.id
}

output "appgw_subnet_id" {
  value = azurerm_subnet.appgw.id
}

output "nat_gateway_id" {
  value = try(azurerm_nat_gateway.this[0].id, null)
}
