# modules/gcp/compute/outputs.tf

output "instance_ids" {
  description = "Instance IDs (self-links in GCP)."
  value       = google_compute_instance_from_template.app[*].instance_id
}

output "instance_self_links" {
  value = google_compute_instance_from_template.app[*].self_link
}

output "instance_names" {
  value = google_compute_instance_from_template.app[*].name
}

output "private_ips" {
  value = [
    for inst in google_compute_instance_from_template.app :
    inst.network_interface[0].network_ip
  ]
}

output "instance_template_id" {
  value = google_compute_instance_template.app.id
}
