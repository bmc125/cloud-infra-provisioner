# modules/gcp/vpc/outputs.tf

output "vpc_id" {
  description = "Self-link of the VPC network."
  value       = google_compute_network.this.self_link
}

output "vpc_name" {
  description = "Name of the VPC network — used in firewall rules and instance network references."
  value       = google_compute_network.this.name
}

output "public_subnet_ids" {
  value = google_compute_subnetwork.public[*].self_link
}

output "private_subnet_ids" {
  value = google_compute_subnetwork.private[*].self_link
}

output "private_subnet_names" {
  description = "Subnet names — needed when creating instances in specific subnets."
  value       = google_compute_subnetwork.private[*].name
}

output "router_name" {
  value = google_compute_router.this.name
}
