# modules/azure/vpc/variables.tf

variable "project" { type = string }
variable "environment" {
  type = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "location" {
  description = "Azure region, e.g. eastus, westeurope."
  type        = string
  default     = "eastus"
}

variable "vnet_cidr" {
  description = "Address space for the Virtual Network."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type = list(string)
}

variable "private_subnet_cidrs" {
  type = list(string)
}

variable "flow_log_retention_days" {
  type    = number
  default = 30
}

variable "common_tags" {
  type    = map(string)
  default = {}
}
