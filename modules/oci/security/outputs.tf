# modules/oci/security/outputs.tf

output "nsg_id" {
  description = "NSG OCID — pass to compute module."
  value       = oci_core_network_security_group.app.id
}

output "dynamic_group_name" {
  value = oci_identity_dynamic_group.app.name
}

output "policy_id" {
  value = oci_identity_policy.app_instance.id
}
