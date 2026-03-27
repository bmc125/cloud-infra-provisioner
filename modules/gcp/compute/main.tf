# modules/gcp/compute/main.tf
#
# Creates GCP Compute Engine instances using an Instance Template.
# Instance Template = GCP equivalent of AWS Launch Template.
# Managed Instance Group (MIG) = equivalent of Auto Scaling Group.
# For simplicity, standalone instances are created here (no MIG).

data "google_compute_image" "cos" {
  # Container-Optimized OS — Google's hardened OS for container workloads.
  # Equivalent to Amazon Linux 2023. Regularly patched, minimal attack surface.
  family  = "cos-stable"
  project = "cos-cloud"
}

# --- Instance Template --------------------------------------------------------

resource "google_compute_instance_template" "app" {
  name_prefix  = "${var.project}-${var.environment}-"
  machine_type = var.machine_type
  region       = var.region
  description  = "Instance template for ${var.project} ${var.environment}"

  disk {
    source_image = var.image != "" ? var.image : data.google_compute_image.cos.self_link
    auto_delete  = true
    boot         = true
    disk_size_gb = var.root_disk_size_gb
    disk_type    = "pd-ssd"

    # Encryption: GCP encrypts all disks by default with Google-managed keys.
    # For CMEK, add a disk_encryption_key block here.
  }

  network_interface {
    subnetwork = var.private_subnet_name
    # No access_config block = no external IP. Egress via Cloud NAT only.
  }

  service_account {
    email  = var.service_account_email
    scopes = ["cloud-platform"] # broad scope; SA permissions control actual access
  }

  tags = concat([var.app_network_tag], var.additional_tags)

  metadata = {
    enable-oslogin        = "TRUE"  # Use OS Login instead of metadata SSH keys
    block-project-ssh-keys = "TRUE" # Prevent project-wide SSH keys from applying
    startup-script        = templatefile("${path.module}/startup_script.sh.tpl", {
      project     = var.project
      environment = var.environment
    })
  }

  labels = merge(var.common_labels, {
    project     = var.project
    environment = var.environment
  })

  lifecycle {
    create_before_destroy = true
  }
}

# --- Compute Instances --------------------------------------------------------

resource "google_compute_instance_from_template" "app" {
  count = var.instance_count

  name                     = "${var.project}-${var.environment}-app-${count.index + 1}"
  zone                     = var.zones[count.index % length(var.zones)]
  source_instance_template = google_compute_instance_template.app.self_link

  labels = merge(var.common_labels, {
    project     = var.project
    environment = var.environment
    index       = tostring(count.index + 1)
  })
}
