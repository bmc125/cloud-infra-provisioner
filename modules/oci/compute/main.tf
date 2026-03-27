# modules/oci/compute/main.tf
#
# OCI Compute instances using the Always Free eligible shape where possible.
# VM.Standard.A1.Flex (Ampere ARM) = OCI's free tier compute shape.
# For paid environments use VM.Standard.E4.Flex (x86).

data "oci_core_images" "oracle_linux" {
  compartment_id           = var.compartment_id
  operating_system         = "Oracle Linux"
  operating_system_version = "8"
  shape                    = var.shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
  state                    = "AVAILABLE"
}

# --- Instances ----------------------------------------------------------------

resource "oci_core_instance" "app" {
  count = var.instance_count

  compartment_id      = var.compartment_id
  availability_domain = var.availability_domains[count.index % length(var.availability_domains)]
  display_name        = "${var.project}-${var.environment}-app-${count.index + 1}"
  shape               = var.shape

  # Flex shapes require OCPUs and memory to be specified.
  shape_config {
    ocpus         = var.ocpus
    memory_in_gbs = var.memory_in_gbs
  }

  create_vnic_details {
    subnet_id              = var.private_subnet_ids[count.index % length(var.private_subnet_ids)]
    assign_public_ip       = false
    nsg_ids                = [var.nsg_id]
    display_name           = "${var.project}-${var.environment}-app-${count.index + 1}-vnic"
    hostname_label         = "${var.project}-${var.environment}-${count.index + 1}"
  }

  source_details {
    source_type             = "image"
    source_id               = var.image_id != "" ? var.image_id : data.oci_core_images.oracle_linux.images[0].id
    boot_volume_size_in_gbs = var.boot_volume_size_gb
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data = base64encode(templatefile("${path.module}/cloud_init.sh.tpl", {
      project     = var.project
      environment = var.environment
    }))
  }

  # Instance principal auth — no credentials on disk, uses dynamic group policy.
  # OCI handles this via the dynamic group + policy in the security module;
  # no extra block needed here unlike AWS instance profiles.

  freeform_tags = merge(var.freeform_tags, {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
    Name        = "${var.project}-${var.environment}-app-${count.index + 1}"
  })
}
