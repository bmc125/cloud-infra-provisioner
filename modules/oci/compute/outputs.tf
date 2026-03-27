# modules/oci/compute/outputs.tf

output "instance_ids" {
  description = "OCIDs of the compute instances."
  value       = oci_core_instance.app[*].id
}

output "instance_names" {
  value = oci_core_instance.app[*].display_name
}

output "private_ips" {
  value = oci_core_instance.app[*].private_ip
}

output "availability_domains" {
  description = "ADs where instances were placed."
  value       = oci_core_instance.app[*].availability_domain
}
