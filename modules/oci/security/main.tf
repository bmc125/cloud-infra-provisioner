# modules/oci/security/main.tf
#
# OCI Network Security Group (instance-level, unlike Security Lists which are subnet-level)
# + Dynamic Group + IAM Policy for instance principal authentication.
#
# OCI instance principal = AWS IAM Instance Profile = GCP Service Account.
# The instance itself becomes the identity — no credentials stored on disk.

# --- Network Security Group ---------------------------------------------------

resource "oci_core_network_security_group" "app" {
  compartment_id = var.compartment_id
  vcn_id         = var.vcn_id
  display_name   = "${var.project}-${var.environment}-app-nsg"
  freeform_tags  = var.freeform_tags
}

# HTTPS inbound
resource "oci_core_network_security_group_security_rule" "https_inbound" {
  network_security_group_id = oci_core_network_security_group.app.id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  description               = "Allow HTTPS from permitted CIDRs"
  stateless                 = false

  source      = var.allowed_ingress_cidr
  source_type = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = 443
      max = 443
    }
  }
}

# HTTP inbound (redirect to HTTPS at app layer)
resource "oci_core_network_security_group_security_rule" "http_inbound" {
  network_security_group_id = oci_core_network_security_group.app.id
  direction                 = "INGRESS"
  protocol                  = "6"
  description               = "Allow HTTP — redirect at app layer"
  stateless                 = false

  source      = var.allowed_ingress_cidr
  source_type = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = 80
      max = 80
    }
  }
}

# SSH inbound — only from specific CIDR, never 0.0.0.0/0 in non-dev
resource "oci_core_network_security_group_security_rule" "ssh_inbound" {
  count = var.enable_ssh ? 1 : 0

  network_security_group_id = oci_core_network_security_group.app.id
  direction                 = "INGRESS"
  protocol                  = "6"
  description               = "Allow SSH from specified CIDRs only"
  stateless                 = false

  source      = var.ssh_allowed_cidr
  source_type = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = 22
      max = 22
    }
  }
}

# All egress
resource "oci_core_network_security_group_security_rule" "all_egress" {
  network_security_group_id = oci_core_network_security_group.app.id
  direction                 = "EGRESS"
  protocol                  = "all"
  description               = "Allow all outbound"
  stateless                 = false

  destination      = "0.0.0.0/0"
  destination_type = "CIDR_BLOCK"
}

# --- Dynamic Group ------------------------------------------------------------
# Groups all instances in the compartment tagged with this project/environment.
# The matching rule uses freeform tags — OCI evaluates this at auth time.

resource "oci_identity_dynamic_group" "app" {
  compartment_id = var.tenancy_id  # Dynamic groups are always in the tenancy (root)
  name           = "${var.project}-${var.environment}-instance-dg"
  description    = "All compute instances for ${var.project} ${var.environment}"

  # Matches any instance in the compartment with matching freeform tags.
  matching_rule = "ALL {instance.compartment.id = '${var.compartment_id}', tag.Project.value = '${var.project}', tag.Environment.value = '${var.environment}'}"
}

# --- IAM Policy ---------------------------------------------------------------
# Grants the dynamic group permission to write logs and metrics.
# Principle of least privilege: only the permissions the instances actually need.

resource "oci_identity_policy" "app_instance" {
  compartment_id = var.compartment_id
  name           = "${var.project}-${var.environment}-instance-policy"
  description    = "Allows ${var.project} ${var.environment} instances to write logs and metrics"

  statements = [
    "Allow dynamic-group ${oci_identity_dynamic_group.app.name} to use log-content in compartment id ${var.compartment_id}",
    "Allow dynamic-group ${oci_identity_dynamic_group.app.name} to read metrics in compartment id ${var.compartment_id}",
    "Allow dynamic-group ${oci_identity_dynamic_group.app.name} to use object-family in compartment id ${var.compartment_id}",
  ]
}
