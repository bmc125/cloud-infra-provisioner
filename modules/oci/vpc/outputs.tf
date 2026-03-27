# modules/oci/vpc/outputs.tf

output "vcn_id" {
  value = oci_core_vcn.this.id
}

output "vcn_cidr" {
  value = var.vcn_cidr
}

output "public_subnet_ids" {
  value = oci_core_subnet.public[*].id
}

output "private_subnet_ids" {
  value = oci_core_subnet.private[*].id
}

output "internet_gateway_id" {
  value = oci_core_internet_gateway.this.id
}

output "nat_gateway_id" {
  value = oci_core_nat_gateway.this.id
}

output "service_gateway_id" {
  value = oci_core_service_gateway.this.id
}

output "log_group_id" {
  value = oci_logging_log_group.vcn.id
}
