# environments/staging/outputs.tf

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "private_subnet_ids" {
  value = module.vpc.private_subnet_ids
}

output "nat_gateway_public_ips" {
  value = module.vpc.nat_gateway_public_ips
}

output "app_security_group_id" {
  value = module.security.app_security_group_id
}

output "instance_ids" {
  value = module.compute.instance_ids
}

output "instance_private_ips" {
  value = module.compute.private_ips
}
