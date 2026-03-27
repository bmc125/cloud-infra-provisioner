# modules/compute/variables.tf

variable "project" { type = string }
variable "environment" {
  type = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "private_subnet_ids" {
  description = "Private subnet IDs to distribute instances across."
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group ID to attach to instances."
  type        = string
}

variable "instance_profile_name" {
  description = "IAM instance profile name for EC2. Pass security module output here."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "t3.micro"
}

variable "ami_id" {
  description = "AMI ID. Leave empty to use the latest Amazon Linux 2023 AMI automatically."
  type        = string
  default     = ""
}

variable "instance_count" {
  description = "Number of EC2 instances to create."
  type        = number
  default     = 1

  validation {
    condition     = var.instance_count >= 1 && var.instance_count <= 10
    error_message = "instance_count must be between 1 and 10."
  }
}

variable "root_volume_size_gb" {
  description = "Root EBS volume size in GB."
  type        = number
  default     = 20
}

variable "common_tags" {
  type    = map(string)
  default = {}
}
