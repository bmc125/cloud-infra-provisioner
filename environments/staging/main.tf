# environments/staging/main.tf
#
# Staging root module. Sits between dev and prod:
#   - Two AZs (like prod topology, unlike dev single-AZ mindset)
#   - Single NAT (cost saving — staging doesn't need full HA)
#   - No bastion — SSM only
#   - Moderate instance sizing

terraform {
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "YOUR-ORG-tf-state-us-east-1"   # CHANGE THIS
    key            = "cloud-infra-provisioner/staging/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = var.owner
      Repo        = "https://github.com/YOUR_USERNAME/cloud-infra-provisioner"
    }
  }
}

module "vpc" {
  source = "../../modules/vpc"

  project     = var.project
  environment = var.environment

  vpc_cidr             = "10.20.0.0/16"
  availability_zones   = ["us-east-1a", "us-east-1b"]
  public_subnet_cidrs  = ["10.20.0.0/24", "10.20.1.0/24"]
  private_subnet_cidrs = ["10.20.10.0/24", "10.20.11.0/24"]

  nat_gateway_count       = 1
  flow_log_retention_days = 30

  common_tags = local.common_tags
}

module "security" {
  source = "../../modules/security"

  project     = var.project
  environment = var.environment
  vpc_id      = module.vpc.vpc_id

  allowed_ingress_cidrs = var.allowed_ingress_cidrs
  enable_bastion        = false

  common_tags = local.common_tags
}

module "compute" {
  source = "../../modules/compute"

  project     = var.project
  environment = var.environment

  private_subnet_ids    = module.vpc.private_subnet_ids
  security_group_id     = module.security.app_security_group_id
  instance_profile_name = module.security.ec2_instance_profile_name

  instance_type       = "t3.micro"
  instance_count      = 2
  root_volume_size_gb = 20

  common_tags = local.common_tags
}

locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
  }
}
