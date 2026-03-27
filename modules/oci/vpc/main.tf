# modules/oci/vpc/main.tf
#
# OCI networking: VCN, public/private subnets, Internet Gateway, NAT Gateway,
# Service Gateway (for OCI service access without public internet), route tables.
#
# OCI terminology (you know these — just mapping them explicitly):
#   AWS VPC            → OCI Virtual Cloud Network (VCN)
#   AWS Subnet         → OCI Subnet (regional, not AZ-scoped — tied to AD)
#   AWS IGW            → OCI Internet Gateway
#   AWS NAT Gateway    → OCI NAT Gateway
#   AWS Security Group → OCI Security List or Network Security Group (NSG)
#   AWS Route Table    → OCI Route Table
#   AWS VPC Flow Logs  → OCI VCN Flow Logs (via OCI Logging service)
#   AWS IAM Role       → OCI Dynamic Group + IAM Policy

resource "oci_core_vcn" "this" {
  compartment_id = var.compartment_id
  cidr_blocks    = [var.vcn_cidr]
  display_name   = "${var.project}-${var.environment}-vcn"
  dns_label      = lower(replace("${var.project}${var.environment}", "-", ""))

  freeform_tags = merge(var.freeform_tags, {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

# --- Gateways -----------------------------------------------------------------

resource "oci_core_internet_gateway" "this" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.project}-${var.environment}-igw"
  enabled        = true

  freeform_tags = var.freeform_tags
}

resource "oci_core_nat_gateway" "this" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.project}-${var.environment}-nat"
  block_traffic  = false

  freeform_tags = var.freeform_tags
}

# Service Gateway allows instances to reach OCI services (Object Storage,
# Streaming, etc.) without traversing the public internet.
data "oci_core_services" "all" {}

resource "oci_core_service_gateway" "this" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.project}-${var.environment}-sgw"

  services {
    service_id = data.oci_core_services.all.services[0].id
  }

  freeform_tags = var.freeform_tags
}

# --- Route Tables -------------------------------------------------------------

resource "oci_core_route_table" "public" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.project}-${var.environment}-rt-public"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.this.id
  }

  freeform_tags = var.freeform_tags
}

resource "oci_core_route_table" "private" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.project}-${var.environment}-rt-private"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.this.id
  }

  route_rules {
    destination       = data.oci_core_services.all.services[0].cidr_block
    destination_type  = "SERVICE_CIDR_BLOCK"
    network_entity_id = oci_core_service_gateway.this.id
  }

  freeform_tags = var.freeform_tags
}

# --- Subnets ------------------------------------------------------------------
# OCI subnets are regional but can be scoped to an Availability Domain.
# Using regional subnets (no ad_name) for flexibility.

resource "oci_core_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  compartment_id    = var.compartment_id
  vcn_id            = oci_core_vcn.this.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  display_name      = "${var.project}-${var.environment}-public-${count.index}"
  dns_label         = "public${count.index}"
  route_table_id    = oci_core_route_table.public.id
  security_list_ids = [oci_core_security_list.public[count.index].id]

  prohibit_public_ip_on_vnic  = false
  prohibit_internet_ingress    = false

  freeform_tags = var.freeform_tags
}

resource "oci_core_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  compartment_id    = var.compartment_id
  vcn_id            = oci_core_vcn.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  display_name      = "${var.project}-${var.environment}-private-${count.index}"
  dns_label         = "private${count.index}"
  route_table_id    = oci_core_route_table.private.id
  security_list_ids = [oci_core_security_list.private[count.index].id]

  prohibit_public_ip_on_vnic = true
  prohibit_internet_ingress   = true

  freeform_tags = var.freeform_tags
}

# --- Security Lists (subnet-level, stateful) ----------------------------------
# OCI Security Lists are subnet-level and stateful.
# OCI also has NSGs (instance-level) — the security module uses those.
# These lists cover baseline subnet rules; NSGs handle app-level rules.

resource "oci_core_security_list" "public" {
  count = length(var.public_subnet_cidrs)

  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.project}-${var.environment}-sl-public-${count.index}"

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
    stateless   = false
  }

  ingress_security_rules {
    protocol  = "6" # TCP
    source    = "0.0.0.0/0"
    stateless = false
    tcp_options { min = 443; max = 443 }
  }

  ingress_security_rules {
    protocol  = "6"
    source    = "0.0.0.0/0"
    stateless = false
    tcp_options { min = 80; max = 80 }
  }

  freeform_tags = var.freeform_tags
}

resource "oci_core_security_list" "private" {
  count = length(var.private_subnet_cidrs)

  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.project}-${var.environment}-sl-private-${count.index}"

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
    stateless   = false
  }

  ingress_security_rules {
    protocol  = "6"
    source    = var.vcn_cidr
    stateless = false
    tcp_options { min = 1; max = 65535 }
  }

  freeform_tags = var.freeform_tags
}

# --- VCN Flow Logs ------------------------------------------------------------

resource "oci_logging_log_group" "vcn" {
  compartment_id = var.compartment_id
  display_name   = "${var.project}-${var.environment}-vcn-log-group"
  freeform_tags  = var.freeform_tags
}

resource "oci_logging_log" "vcn_flow" {
  display_name = "${var.project}-${var.environment}-vcn-flow-log"
  log_group_id = oci_logging_log_group.vcn.id
  log_type     = "SERVICE"

  configuration {
    source {
      category    = "all"
      resource    = oci_core_vcn.this.id
      service     = "flowlogs"
      source_type = "OCISERVICE"
    }
    compartment_id = var.compartment_id
  }

  retention_duration = var.flow_log_retention_days
  is_enabled         = true

  freeform_tags = var.freeform_tags
}
