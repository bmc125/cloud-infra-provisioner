# modules/vpc/outputs.tf
# These values are consumed by the compute and security modules.
# Output everything a caller might need — callers can ignore what they don't use.

output "vpc_id" {
  description = "ID of the created VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "List of public subnet IDs, in AZ order."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs, in AZ order."
  value       = aws_subnet.private[*].id
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway."
  value       = aws_internet_gateway.this.id
}

output "nat_gateway_ids" {
  description = "IDs of NAT Gateways created."
  value       = aws_nat_gateway.this[*].id
}

output "nat_gateway_public_ips" {
  description = "Public IPs of NAT Gateways — useful for allowlisting outbound traffic at third-party firewalls."
  value       = aws_eip.nat[*].public_ip
}
