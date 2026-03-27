# environments/ENV/variables.tf
variable "cloud_provider" {
  description = "Cloud provider: aws, gcp, azure, or oci."
  type        = string
  validation {
    condition     = contains(["aws", "gcp", "azure", "oci"], var.cloud_provider)
    error_message = "cloud_provider must be one of: aws, gcp, azure, oci."
  }
}
variable "project" { type = string; default = "infra-demo" }
variable "environment" { type = string }
variable "owner" { type = string; default = "platform-team" }
variable "my_ip_cidr" { type = string; default = "10.0.0.1/32" }
variable "ssh_public_key" { type = string; sensitive = true; default = "" }
variable "aws_region" { type = string; default = "us-east-1" }
variable "gcp_project_id" { type = string; default = "" }
variable "gcp_region" { type = string; default = "us-central1" }
variable "azure_subscription_id" { type = string; default = ""; sensitive = true }
variable "azure_location" { type = string; default = "eastus" }
variable "oci_tenancy_id" { type = string; default = ""; sensitive = true }
variable "oci_user_id" { type = string; default = ""; sensitive = true }
variable "oci_fingerprint" { type = string; default = ""; sensitive = true }
variable "oci_private_key_path" { type = string; default = "~/.oci/oci_api_key.pem" }
variable "oci_region" { type = string; default = "us-ashburn-1" }
variable "oci_compartment_id" { type = string; default = ""; sensitive = true }
variable "oci_availability_domains" { type = list(string); default = ["AD-1"] }
variable "allowed_ingress_cidrs" { type = list(string); default = ["0.0.0.0/0"] }
