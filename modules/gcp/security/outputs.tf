# modules/gcp/security/outputs.tf

output "app_network_tag" {
  description = "Network tag to assign to compute instances to apply firewall rules."
  value       = "app-server"
}

output "service_account_email" {
  description = "Service account email — assign to compute instances."
  value       = google_service_account.app.email
}

output "service_account_id" {
  value = google_service_account.app.id
}
