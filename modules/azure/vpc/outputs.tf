# modules/azure/vpc/outputs.tf

output "resource_group_name" {
  description = "Resource group name — all other modules need this."
  value       = azurerm_resource_group.this.name
}

output "resource_group_location" {
  value = azurerm_resource_group.this.location
}

output "vnet_id" {
  value = azurerm_virtual_network.this.id
}

output "vnet_name" {
  value = azurerm_virtual_network.this.name
}

output "public_subnet_ids" {
  value = azurerm_subnet.public[*].id
}

output "private_subnet_ids" {
  value = azurerm_subnet.private[*].id
}

output "nat_gateway_id" {
  value = azurerm_nat_gateway.this.id
}

output "nat_public_ip" {
  value = azurerm_public_ip.nat.ip_address
}

output "flow_logs_storage_account_id" {
  value = azurerm_storage_account.flow_logs.id
}

output "network_watcher_id" {
  value = azurerm_network_watcher.this.id
}
