# modules/gcp/vpc/variables.tf

variable "project" { type = string }
variable "environment" {
  type = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "gcp_project_id" {
  description = "GCP project ID (not the display name — the unique ID like 'my-project-123456')."
  type        = string
}

variable "region" {
  description = "GCP region, e.g. us-central1."
  type        = string
  default     = "us-central1"
}

variable "public_subnet_cidrs" {
  description = "CIDR ranges for public subnets."
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR ranges for private subnets."
  type        = list(string)
}

variable "flow_log_retention_days" {
  description = "Unused in GCP (flow logs are always-on per subnet). Kept for interface parity."
  type        = number
  default     = 30
}

variable "common_labels" {
  description = "Labels applied to all resources. GCP uses labels, not tags."
  type        = map(string)
  default     = {}
}
