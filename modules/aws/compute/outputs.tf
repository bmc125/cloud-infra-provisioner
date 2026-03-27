# modules/compute/outputs.tf

output "instance_ids" {
  description = "List of EC2 instance IDs created."
  value       = aws_instance.app[*].id
}

output "private_ips" {
  description = "Private IP addresses of instances."
  value       = aws_instance.app[*].private_ip
}

output "launch_template_id" {
  description = "Launch template ID — needed if you add an ASG later."
  value       = aws_launch_template.app.id
}

output "launch_template_latest_version" {
  description = "Latest version number of the launch template."
  value       = aws_launch_template.app.latest_version
}
