# modules/security/outputs.tf

output "app_security_group_id" {
  description = "Security group ID for application instances."
  value       = aws_security_group.app.id
}

output "bastion_security_group_id" {
  description = "Security group ID for bastion host. Null if enable_bastion = false."
  value       = var.enable_bastion ? aws_security_group.bastion[0].id : null
}

output "ec2_instance_profile_name" {
  description = "IAM instance profile name — attach to EC2 launch templates."
  value       = aws_iam_instance_profile.ec2.name
}

output "ec2_iam_role_arn" {
  description = "ARN of the EC2 IAM role."
  value       = aws_iam_role.ec2_instance.arn
}
