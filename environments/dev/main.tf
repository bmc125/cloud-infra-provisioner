# environments/dev/main.tf
#
# Multi-cloud root module for the dev environment.
# Set var.cloud_provider to "aws", "gcp", "azure", or "oci".
# Only the selected provider's resources are created — the others produce no resources.
#
# WHY THIS PATTERN (not a "universal module"):
# Terraform does not support dynamic module sources. Each cloud has fundamentally
# different resource models — pretending they share one interface creates lies in
# the abstraction. Each cloud block is fully explicit and gated by a local bool.

terraform {
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    oci = {
      source  = "oracle/oci"
      version = "~> 5.0"
    }
  }

  # Choose ONE backend and comment out the others.
  backend "s3" {
    bucket         = "YOUR-ORG-tf-state-us-east-1"  # CHANGE THIS
    key            = "cloud-infra-provisioner/dev/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
  # backend "gcs" {
  #   bucket = "YOUR-ORG-tf-state"
  #   prefix = "cloud-infra-provisioner/dev"
  # }
  # backend "azurerm" {
  #   resource_group_name  = "YOUR-ORG-tfstate-rg"
  #   storage_account_name = "yourorgtfstate"
  #   container_name       = "tfstate"
  #   key                  = "cloud-infra-provisioner/dev/terraform.tfstate"
  # }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project       = var.project
      Environment   = var.environment
      ManagedBy     = "terraform"
      Owner         = var.owner
      CloudProvider = "aws"
    }
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

provider "azurerm" {
  features {}
  subscription_id = var.azure_subscription_id
}

provider "oci" {
  tenancy_ocid     = var.oci_tenancy_id
  user_ocid        = var.oci_user_id
  fingerprint      = var.oci_fingerprint
  private_key_path = var.oci_private_key_path
  region           = var.oci_region
}

locals {
  is_aws   = var.cloud_provider == "aws"
  is_gcp   = var.cloud_provider == "gcp"
  is_azure = var.cloud_provider == "azure"
  is_oci   = var.cloud_provider == "oci"

  common_tags = {
    Project       = var.project
    Environment   = var.environment
    ManagedBy     = "terraform"
    CloudProvider = var.cloud_provider
  }
}

# ---------------------------------------------------------------------------
# AWS
# ---------------------------------------------------------------------------

module "aws_vpc" {
  count  = local.is_aws ? 1 : 0
  source = "../../modules/aws/vpc"

  project     = var.project
  environment = var.environment

  vpc_cidr             = "10.10.0.0/16"
  availability_zones   = ["us-east-1a", "us-east-1b"]
  public_subnet_cidrs  = ["10.10.0.0/24", "10.10.1.0/24"]
  private_subnet_cidrs = ["10.10.10.0/24", "10.10.11.0/24"]

  nat_gateway_count       = 1
  flow_log_retention_days = 14
  common_tags             = local.common_tags
}

module "aws_security" {
  count  = local.is_aws ? 1 : 0
  source = "../../modules/aws/security"

  project               = var.project
  environment           = var.environment
  vpc_id                = module.aws_vpc[0].vpc_id
  allowed_ingress_cidrs = ["0.0.0.0/0"]
  enable_bastion        = true
  bastion_allowed_cidrs = [var.my_ip_cidr]
  common_tags           = local.common_tags
}

module "aws_compute" {
  count  = local.is_aws ? 1 : 0
  source = "../../modules/aws/compute"

  project               = var.project
  environment           = var.environment
  private_subnet_ids    = module.aws_vpc[0].private_subnet_ids
  security_group_id     = module.aws_security[0].app_security_group_id
  instance_profile_name = module.aws_security[0].ec2_instance_profile_name
  instance_type         = "t3.micro"
  instance_count        = 1
  root_volume_size_gb   = 20
  common_tags           = local.common_tags
}

# ---------------------------------------------------------------------------
# GCP
# ---------------------------------------------------------------------------

module "gcp_vpc" {
  count  = local.is_gcp ? 1 : 0
  source = "../../modules/gcp/vpc"

  project              = var.project
  environment          = var.environment
  gcp_project_id       = var.gcp_project_id
  region               = var.gcp_region
  public_subnet_cidrs  = ["10.10.0.0/24"]
  private_subnet_cidrs = ["10.10.10.0/24"]
  common_labels        = local.common_tags
}

module "gcp_security" {
  count  = local.is_gcp ? 1 : 0
  source = "../../modules/gcp/security"

  project               = var.project
  environment           = var.environment
  gcp_project_id        = var.gcp_project_id
  vpc_name              = module.gcp_vpc[0].vpc_name
  allowed_ingress_cidrs = ["0.0.0.0/0"]
  enable_iap_ssh        = true
  common_labels         = local.common_tags
}

module "gcp_compute" {
  count  = local.is_gcp ? 1 : 0
  source = "../../modules/gcp/compute"

  project               = var.project
  environment           = var.environment
  region                = var.gcp_region
  zones                 = ["${var.gcp_region}-a", "${var.gcp_region}-b"]
  private_subnet_name   = module.gcp_vpc[0].private_subnet_names[0]
  service_account_email = module.gcp_security[0].service_account_email
  app_network_tag       = module.gcp_security[0].app_network_tag
  machine_type          = "e2-micro"
  instance_count        = 1
  root_disk_size_gb     = 20
  common_labels         = local.common_tags
}

# ---------------------------------------------------------------------------
# Azure
# ---------------------------------------------------------------------------

module "azure_vpc" {
  count  = local.is_azure ? 1 : 0
  source = "../../modules/azure/vpc"

  project              = var.project
  environment          = var.environment
  location             = var.azure_location
  vnet_cidr            = "10.10.0.0/16"
  public_subnet_cidrs  = ["10.10.0.0/24"]
  private_subnet_cidrs = ["10.10.10.0/24"]
  common_tags          = local.common_tags
}

module "azure_security" {
  count  = local.is_azure ? 1 : 0
  source = "../../modules/azure/security"

  project               = var.project
  environment           = var.environment
  location              = var.azure_location
  resource_group_name   = module.azure_vpc[0].resource_group_name
  vnet_name             = module.azure_vpc[0].vnet_name
  subscription_id       = var.azure_subscription_id
  private_subnet_ids    = module.azure_vpc[0].private_subnet_ids
  allowed_ingress_cidrs = ["0.0.0.0/0"]
  enable_bastion        = false
  common_tags           = local.common_tags
}

module "azure_compute" {
  count  = local.is_azure ? 1 : 0
  source = "../../modules/azure/compute"

  project              = var.project
  environment          = var.environment
  location             = var.azure_location
  resource_group_name  = module.azure_vpc[0].resource_group_name
  private_subnet_ids   = module.azure_vpc[0].private_subnet_ids
  nsg_id               = module.azure_security[0].nsg_id
  managed_identity_id  = module.azure_security[0].managed_identity_id
  vm_size              = "Standard_B1s"
  instance_count       = 1
  os_disk_size_gb      = 30
  admin_ssh_public_key = var.ssh_public_key
  common_tags          = local.common_tags
}

# ---------------------------------------------------------------------------
# OCI
# ---------------------------------------------------------------------------

module "oci_vpc" {
  count  = local.is_oci ? 1 : 0
  source = "../../modules/oci/vpc"

  project              = var.project
  environment          = var.environment
  compartment_id       = var.oci_compartment_id
  vcn_cidr             = "10.10.0.0/16"
  public_subnet_cidrs  = ["10.10.0.0/24"]
  private_subnet_cidrs = ["10.10.10.0/24"]
  freeform_tags        = local.common_tags
}

module "oci_security" {
  count  = local.is_oci ? 1 : 0
  source = "../../modules/oci/security"

  project              = var.project
  environment          = var.environment
  compartment_id       = var.oci_compartment_id
  tenancy_id           = var.oci_tenancy_id
  vcn_id               = module.oci_vpc[0].vcn_id
  allowed_ingress_cidr = "0.0.0.0/0"
  enable_ssh           = true
  ssh_allowed_cidr     = var.my_ip_cidr
  freeform_tags        = local.common_tags
}

module "oci_compute" {
  count  = local.is_oci ? 1 : 0
  source = "../../modules/oci/compute"

  project              = var.project
  environment          = var.environment
  compartment_id       = var.oci_compartment_id
  availability_domains = var.oci_availability_domains
  private_subnet_ids   = module.oci_vpc[0].private_subnet_ids
  nsg_id               = module.oci_security[0].nsg_id
  shape                = "VM.Standard.A1.Flex"
  ocpus                = 1
  memory_in_gbs        = 6
  instance_count       = 1
  ssh_public_key       = var.ssh_public_key
  freeform_tags        = local.common_tags
}
