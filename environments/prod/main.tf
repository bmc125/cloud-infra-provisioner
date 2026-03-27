# environments/prod/main.tf
#
# Prod root module. Key differences from dev:
#   - Multi-AZ NAT Gateways (no SPOF)
#   - No bastion (use SSM Session Manager)
#   - Restricted ingress CIDRs
#   - Longer log retention
#   - Larger instances and higher instance count
#   - Separate state key

terraform {
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "YOUR-ORG-tf-state-us-east-1"   # CHANGE THIS — same bucket, different key
    key            = "cloud-infra-provisioner/prod/terraform.tfstate"
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

  vpc_cidr             = "10.30.0.0/16"  # non-overlapping with dev (10.10) and staging (10.20)
  availability_zones   = ["us-east-1a", "us-east-1b", "us-east-1c"]
  public_subnet_cidrs  = ["10.30.0.0/24", "10.30.1.0/24", "10.30.2.0/24"]
  private_subnet_cidrs = ["10.30.10.0/24", "10.30.11.0/24", "10.30.12.0/24"]

  nat_gateway_count       = 3   # one per AZ — required for prod HA
  flow_log_retention_days = 90

  common_tags = local.common_tags
}

module "security" {
  source = "../../modules/security"

  project     = var.project
  environment = var.environment
  vpc_id      = module.vpc.vpc_id

  # Prod: restrict to your load balancer or Cloudflare IP ranges, not 0.0.0.0/0
  allowed_ingress_cidrs = var.allowed_ingress_cidrs

  enable_bastion = false  # use SSM Session Manager in prod

  common_tags = local.common_tags
}

module "compute" {
  source = "../../modules/compute"

  project     = var.project
  environment = var.environment

  private_subnet_ids    = module.vpc.private_subnet_ids
  security_group_id     = module.security.app_security_group_id
  instance_profile_name = module.security.ec2_instance_profile_name

  instance_type       = "t3.small"
  instance_count      = 3         # one per AZ
  root_volume_size_gb = 30

  common_tags = local.common_tags
}

locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
  }
}
