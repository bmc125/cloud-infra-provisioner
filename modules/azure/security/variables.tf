# modules/azure/security/variables.tf

variable "project" { type = string }
variable "environment" {
  type = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "vnet_name" { type = string }
variable "subscription_id" { type = string }

variable "private_subnet_ids" {
  description = "Private subnet IDs to associate the NSG with."
  type        = list(string)
}

variable "allowed_ingress_cidrs" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}

variable "enable_bastion" {
  description = "Deploy Azure Bastion for managed SSH/RDP access. Costs ~$140/month — consider for prod only."
  type        = bool
  default     = false
}

variable "bastion_subnet_cidr" {
  description = "CIDR for AzureBastionSubnet. Must be /26 or larger."
  type        = string
  default     = "10.0.255.0/26"
}

variable "common_tags" {
  type    = map(string)
  default = {}
}
