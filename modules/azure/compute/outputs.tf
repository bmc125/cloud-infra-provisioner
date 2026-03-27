# modules/azure/compute/outputs.tf

output "instance_ids" {
  description = "Azure VM resource IDs."
  value       = azurerm_linux_virtual_machine.app[*].id
}

output "instance_names" {
  value = azurerm_linux_virtual_machine.app[*].name
}

output "private_ips" {
  value = azurerm_network_interface.app[*].private_ip_address
}

output "nic_ids" {
  value = azurerm_network_interface.app[*].id
}
