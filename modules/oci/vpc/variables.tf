# modules/oci/vpc/variables.tf

variable "project" { type = string }
variable "environment" {
  type = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "compartment_id" {
  description = "OCID of the compartment to deploy into."
  type        = string
}

variable "vcn_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type = list(string)
}

variable "private_subnet_cidrs" {
  type = list(string)
}

variable "flow_log_retention_days" {
  description = "Log retention in days. OCI Logging accepts 30, 60, 90, 120, or 180."
  type        = number
  default     = 30

  validation {
    condition     = contains([30, 60, 90, 120, 180], var.flow_log_retention_days)
    error_message = "OCI flow log retention must be 30, 60, 90, 120, or 180 days."
  }
}

variable "freeform_tags" {
  description = "OCI freeform tags (key-value pairs). OCI uses freeform_tags, not tags."
  type        = map(string)
  default     = {}
}
