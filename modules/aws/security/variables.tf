# modules/security/variables.tf

variable "project" {
  type = string
}

variable "environment" {
  type = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "vpc_id" {
  description = "VPC ID to attach security groups to. Pass vpc module output here."
  type        = string
}

variable "allowed_ingress_cidrs" {
  description = "CIDRs allowed to reach the application tier on HTTP/HTTPS."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_bastion" {
  description = "Whether to create a bastion security group. Set false in prod — use SSM instead."
  type        = bool
  default     = false
}

variable "bastion_allowed_cidrs" {
  description = "CIDRs allowed SSH access to the bastion. Must be specific IPs — never 0.0.0.0/0."
  type        = list(string)
  default     = []

  validation {
    condition     = !contains(var.bastion_allowed_cidrs, "0.0.0.0/0")
    error_message = "0.0.0.0/0 is not allowed as a bastion SSH CIDR. Use your actual IP."
  }
}

variable "common_tags" {
  type    = map(string)
  default = {}
}
