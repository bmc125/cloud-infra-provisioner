# modules/gcp/vpc/main.tf
#
# GCP networking: VPC (custom mode), regional subnets, Cloud Router + NAT.
#
# GCP difference from AWS worth knowing:
#   - GCP VPCs are global — subnets are regional, not AZ-scoped.
#   - There is no Internet Gateway resource; external IPs and Cloud NAT handle egress.
#   - Firewall rules are VPC-level (not subnet-level), applied via network tags on instances.
#   - "Availability zones" map to GCP regions/zones but subnets are regional.

resource "google_compute_network" "this" {
  name                    = "${var.project}-${var.environment}-vpc"
  auto_create_subnetworks = false # custom mode — we define subnets explicitly
  description             = "VPC for ${var.project} ${var.environment}"
}

# --- Subnets -------------------------------------------------------------------
# GCP subnets are regional. Private Google Access allows instances without external
# IPs to reach Google APIs (Cloud Storage, Secret Manager, etc.) without Cloud NAT.

resource "google_compute_subnetwork" "public" {
  count = length(var.public_subnet_cidrs)

  name          = "${var.project}-${var.environment}-public-${count.index}"
  ip_cidr_range = var.public_subnet_cidrs[count.index]
  region        = var.region
  network       = google_compute_network.this.id

  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_subnetwork" "private" {
  count = length(var.private_subnet_cidrs)

  name          = "${var.project}-${var.environment}-private-${count.index}"
  ip_cidr_range = var.private_subnet_cidrs[count.index]
  region        = var.region
  network       = google_compute_network.this.id

  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# --- Cloud Router + NAT --------------------------------------------------------
# Cloud Router is required for Cloud NAT. One router per region is sufficient.

resource "google_compute_router" "this" {
  name    = "${var.project}-${var.environment}-router"
  region  = var.region
  network = google_compute_network.this.id
}

resource "google_compute_router_nat" "this" {
  name                               = "${var.project}-${var.environment}-nat"
  router                             = google_compute_router.this.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  dynamic "subnetwork" {
    for_each = google_compute_subnetwork.private
    content {
      name                    = subnetwork.value.id
      source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
    }
  }

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# --- VPC Flow Logs are configured per-subnet above (log_config blocks) ---------
# GCP doesn't have a separate flow log resource like AWS — it's a subnet property.
