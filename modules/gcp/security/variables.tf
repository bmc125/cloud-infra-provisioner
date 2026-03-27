# modules/gcp/security/variables.tf

variable "project" { type = string }
variable "environment" {
  type = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "gcp_project_id" {
  description = "GCP project ID."
  type        = string
}

variable "vpc_name" {
  description = "VPC network name — pass gcp/vpc module output vpc_name here."
  type        = string
}

variable "allowed_ingress_cidrs" {
  description = "CIDRs allowed to reach app instances on HTTP/HTTPS."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "internal_cidrs" {
  description = "Internal VPC CIDRs for intra-VPC traffic rules."
  type        = list(string)
  default     = ["10.0.0.0/8"]
}

variable "enable_iap_ssh" {
  description = "Allow SSH via Identity-Aware Proxy. Preferred over a bastion in GCP."
  type        = bool
  default     = true
}

variable "common_labels" {
  type    = map(string)
  default = {}
}
