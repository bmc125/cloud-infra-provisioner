# environments/dev/outputs.tf
# Outputs are conditional — only the active provider returns real values.

output "cloud_provider" {
  description = "The active cloud provider for this deployment."
  value       = var.cloud_provider
}

# AWS outputs
output "aws_vpc_id" {
  value = local.is_aws ? module.aws_vpc[0].vpc_id : null
}
output "aws_instance_ids" {
  value = local.is_aws ? module.aws_compute[0].instance_ids : null
}
output "aws_nat_public_ips" {
  value = local.is_aws ? module.aws_vpc[0].nat_gateway_public_ips : null
}

# GCP outputs
output "gcp_vpc_name" {
  value = local.is_gcp ? module.gcp_vpc[0].vpc_name : null
}
output "gcp_instance_names" {
  value = local.is_gcp ? module.gcp_compute[0].instance_names : null
}

# Azure outputs
output "azure_resource_group" {
  value = local.is_azure ? module.azure_vpc[0].resource_group_name : null
}
output "azure_vnet_id" {
  value = local.is_azure ? module.azure_vpc[0].vnet_id : null
}
output "azure_instance_ids" {
  value = local.is_azure ? module.azure_compute[0].instance_ids : null
}

# OCI outputs
output "oci_vcn_id" {
  value = local.is_oci ? module.oci_vpc[0].vcn_id : null
}
output "oci_instance_ids" {
  value = local.is_oci ? module.oci_compute[0].instance_ids : null
}
