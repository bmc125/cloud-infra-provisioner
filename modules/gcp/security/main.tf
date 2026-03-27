# modules/gcp/security/main.tf
#
# GCP firewall rules + service account (equivalent to AWS security groups + IAM role).
#
# Key GCP difference: firewall rules are network-scoped, not instance-scoped.
# They are applied to instances via network tags (strings on the instance).
# The tag "app-server" on an instance means "apply rules targeting app-server".

# --- Firewall: allow HTTP/HTTPS to app-server tagged instances -----------------

resource "google_compute_firewall" "app_https" {
  name    = "${var.project}-${var.environment}-allow-https"
  network = var.vpc_name

  allow {
    protocol = "tcp"
    ports    = ["443", "80"]
  }

  source_ranges = var.allowed_ingress_cidrs
  target_tags   = ["app-server"]

  description = "Allow HTTP/HTTPS to app-server instances from permitted CIDRs."
}

# --- Firewall: allow internal traffic within the VPC --------------------------

resource "google_compute_firewall" "internal" {
  name    = "${var.project}-${var.environment}-allow-internal"
  network = var.vpc_name

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = var.internal_cidrs
  target_tags   = ["app-server"]

  description = "Allow all internal VPC traffic between app instances."
}

# --- Firewall: SSH via IAP (Identity-Aware Proxy) -----------------------------
# GCP's equivalent of AWS SSM Session Manager.
# IAP tunnels SSH through Google's infrastructure — no bastion needed.
# The source range 35.235.240.0/20 is Google's IAP IP range (official, not arbitrary).

resource "google_compute_firewall" "iap_ssh" {
  count = var.enable_iap_ssh ? 1 : 0

  name    = "${var.project}-${var.environment}-allow-iap-ssh"
  network = var.vpc_name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"] # Google IAP range — do not change
  target_tags   = ["app-server"]

  description = "Allow SSH via Identity-Aware Proxy tunnel only. Never 0.0.0.0/0."
}

# --- Service Account ----------------------------------------------------------
# Instances run as this SA. Grant only the permissions needed (principle of least privilege).
# Equivalent to AWS IAM instance role.

resource "google_service_account" "app" {
  account_id   = "${var.project}-${var.environment}-app-sa"
  display_name = "${var.project} ${var.environment} app instances"
  description  = "Service account for ${var.project} ${var.environment} compute instances."
}

# Allow instances to write logs to Cloud Logging
resource "google_project_iam_member" "logging" {
  project = var.gcp_project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.app.email}"
}

# Allow instances to write metrics to Cloud Monitoring
resource "google_project_iam_member" "monitoring" {
  project = var.gcp_project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.app.email}"
}
