# modules/azure/security/outputs.tf

output "nsg_id" {
  description = "Network Security Group ID."
  value       = azurerm_network_security_group.app.id
}

output "managed_identity_id" {
  description = "User-assigned managed identity resource ID — attach to VM identity block."
  value       = azurerm_user_assigned_identity.app.id
}

output "managed_identity_principal_id" {
  description = "Principal ID used for role assignments."
  value       = azurerm_user_assigned_identity.app.principal_id
}

output "managed_identity_client_id" {
  description = "Client ID used inside the VM to acquire tokens."
  value       = azurerm_user_assigned_identity.app.client_id
}

output "bastion_host_id" {
  description = "Azure Bastion ID. Null if enable_bastion = false."
  value       = var.enable_bastion ? azurerm_bastion_host.this[0].id : null
}
