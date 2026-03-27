# modules/azure/compute/variables.tf

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

variable "private_subnet_ids" {
  description = "Private subnet IDs for VM NICs."
  type        = list(string)
}

variable "nsg_id" {
  description = "NSG ID to associate with each NIC."
  type        = string
}

variable "managed_identity_id" {
  description = "User-assigned managed identity resource ID."
  type        = string
}

variable "vm_size" {
  description = "Azure VM size. Standard_B1s is the cheapest for dev/testing."
  type        = string
  default     = "Standard_B1s"
}

variable "os_disk_size_gb" {
  type    = number
  default = 30
}

variable "instance_count" {
  type    = number
  default = 1
  validation {
    condition     = var.instance_count >= 1 && var.instance_count <= 10
    error_message = "instance_count must be between 1 and 10."
  }
}

variable "admin_ssh_public_key" {
  description = "SSH public key for the azureuser account. Use ssh-keygen to generate."
  type        = string
  sensitive   = true
}

variable "common_tags" {
  type    = map(string)
  default = {}
}
