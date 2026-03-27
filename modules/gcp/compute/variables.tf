# modules/gcp/compute/variables.tf

variable "project" { type = string }
variable "environment" {
  type = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "region" {
  description = "GCP region."
  type        = string
}

variable "zones" {
  description = "GCP zones to distribute instances across. e.g. [us-central1-a, us-central1-b]"
  type        = list(string)
}

variable "private_subnet_name" {
  description = "Subnet name for instance NICs — pass gcp/vpc module output private_subnet_names[0]."
  type        = string
}

variable "service_account_email" {
  description = "Service account email — pass gcp/security module output."
  type        = string
}

variable "app_network_tag" {
  description = "Network tag that applies firewall rules — pass gcp/security module output."
  type        = string
  default     = "app-server"
}

variable "additional_tags" {
  description = "Extra network tags to assign to instances."
  type        = list(string)
  default     = []
}

variable "machine_type" {
  description = "GCP machine type. e2-micro is free-tier eligible."
  type        = string
  default     = "e2-micro"
}

variable "image" {
  description = "Source image self_link. Leave empty to use latest Container-Optimized OS."
  type        = string
  default     = ""
}

variable "instance_count" {
  description = "Number of instances to create."
  type        = number
  default     = 1
  validation {
    condition     = var.instance_count >= 1 && var.instance_count <= 10
    error_message = "instance_count must be between 1 and 10."
  }
}

variable "root_disk_size_gb" {
  description = "Boot disk size in GB."
  type        = number
  default     = 20
}

variable "common_labels" {
  type    = map(string)
  default = {}
}
