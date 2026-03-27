# modules/oci/compute/variables.tf

variable "project" { type = string }
variable "environment" {
  type = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "compartment_id" { type = string }

variable "availability_domains" {
  description = "List of AD names in the region. Get via: oci iam availability-domain list"
  type        = list(string)
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "nsg_id" {
  description = "NSG OCID from oci/security module."
  type        = string
}

variable "shape" {
  description = "Compute shape. VM.Standard.A1.Flex is Always Free (ARM). VM.Standard.E4.Flex is x86."
  type        = string
  default     = "VM.Standard.A1.Flex"
}

variable "ocpus" {
  description = "Number of OCPUs per instance. Always Free allows 4 total across all A1 instances."
  type        = number
  default     = 1
}

variable "memory_in_gbs" {
  description = "Memory in GB per instance. Always Free allows 24 GB total across A1 instances."
  type        = number
  default     = 6
}

variable "boot_volume_size_gb" {
  type    = number
  default = 50
}

variable "instance_count" {
  type    = number
  default = 1
  validation {
    condition     = var.instance_count >= 1 && var.instance_count <= 10
    error_message = "instance_count must be between 1 and 10."
  }
}

variable "image_id" {
  description = "Explicit image OCID. Leave empty to auto-select latest Oracle Linux 8."
  type        = string
  default     = ""
}

variable "ssh_public_key" {
  description = "SSH public key content for the opc user."
  type        = string
  sensitive   = true
}

variable "freeform_tags" {
  type    = map(string)
  default = {}
}
