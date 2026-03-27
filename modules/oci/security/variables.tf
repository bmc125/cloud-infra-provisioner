# modules/oci/security/variables.tf

variable "project" { type = string }
variable "environment" {
  type = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "compartment_id" {
  description = "OCID of the compartment."
  type        = string
}

variable "tenancy_id" {
  description = "OCID of the tenancy root — required for dynamic group creation."
  type        = string
}

variable "vcn_id" {
  description = "VCN OCID — pass oci/vpc module output vcn_id."
  type        = string
}

variable "allowed_ingress_cidr" {
  description = "Single CIDR for HTTP/HTTPS ingress. OCI NSG rules take one CIDR per rule."
  type        = string
  default     = "0.0.0.0/0"
}

variable "enable_ssh" {
  description = "Create an SSH ingress rule. Set false in prod."
  type        = bool
  default     = false
}

variable "ssh_allowed_cidr" {
  description = "CIDR allowed SSH access. Never use 0.0.0.0/0."
  type        = string
  default     = "10.0.0.0/8"

  validation {
    condition     = var.ssh_allowed_cidr != "0.0.0.0/0"
    error_message = "0.0.0.0/0 is not allowed as an SSH source CIDR."
  }
}

variable "freeform_tags" {
  type    = map(string)
  default = {}
}
