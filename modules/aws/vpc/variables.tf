# modules/vpc/variables.tf

variable "project" {
  description = "Project name — used as a prefix on all resource names and tags."
  type        = string
}

variable "environment" {
  description = "Deployment environment: dev, staging, or prod."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC. Must not overlap with other VPCs you intend to peer."
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of AZs to deploy into. Length must match public and private subnet CIDR lists."
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets — one per AZ."
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets — one per AZ."
  type        = list(string)
}

variable "nat_gateway_count" {
  description = <<-EOT
    Number of NAT Gateways to create.
    - 1 = single NAT (dev/staging cost optimization, AZ SPOF accepted)
    - length(availability_zones) = one per AZ (prod HA requirement)
  EOT
  type        = number
  default     = 1

  validation {
    condition     = var.nat_gateway_count >= 1
    error_message = "nat_gateway_count must be at least 1."
  }
}

variable "flow_log_retention_days" {
  description = "CloudWatch log retention in days for VPC flow logs."
  type        = number
  default     = 30
}

variable "common_tags" {
  description = "Tags applied to every resource in this module. Merge with resource-specific tags."
  type        = map(string)
  default     = {}
}
