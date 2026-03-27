# modules/azure/compute/main.tf
#
# Azure Linux Virtual Machines via a VM Scale Set (VMSS) in Flexible Orchestration mode.
# Flexible mode lets you manage individual VMs while still getting AZ distribution.
# For standalone VMs without autoscaling, azurerm_linux_virtual_machine resources
# are used directly here (simpler for a portfolio project).
#
# Azure VM terminology:
#   AWS Launch Template → Azure VM Image / VM configuration
#   AWS EC2 Instance    → Azure Linux Virtual Machine
#   AWS EBS Volume      → Azure Managed Disk
#   AWS IMDSv2          → Azure IMDS (v2 requires a header, always enforced in Azure)

resource "azurerm_linux_virtual_machine" "app" {
  count = var.instance_count

  name                = "${var.project}-${var.environment}-app-${count.index + 1}"
  resource_group_name = var.resource_group_name
  location            = var.location
  size                = var.vm_size
  admin_username      = "azureuser"

  # Disable password auth — SSH keys or Azure AD login only.
  disable_password_authentication = true

  # SSH key — in production, source this from a Key Vault secret or variable.
  admin_ssh_key {
    username   = "azureuser"
    public_key = var.admin_ssh_public_key
  }

  network_interface_ids = [azurerm_network_interface.app[count.index].id]

  os_disk {
    name                 = "${var.project}-${var.environment}-app-${count.index + 1}-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = var.os_disk_size_gb

    # Azure encrypts managed disks by default with platform-managed keys.
    # For customer-managed keys, add disk_encryption_set_id here.
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  # User-assigned managed identity for Azure service authentication.
  identity {
    type         = "UserAssigned"
    identity_ids = [var.managed_identity_id]
  }

  # Azure IMDS is always v2-capable. No extra config needed (unlike AWS).
  # custom_data runs on first boot via cloud-init.
  custom_data = base64encode(templatefile("${path.module}/cloud_init.yaml.tpl", {
    project     = var.project
    environment = var.environment
  }))

  tags = merge(var.common_tags, {
    Name        = "${var.project}-${var.environment}-app-${count.index + 1}"
    Environment = var.environment
    Project     = var.project
    ManagedBy   = "terraform"
  })
}

# --- Network Interfaces -------------------------------------------------------

resource "azurerm_network_interface" "app" {
  count = var.instance_count

  name                = "${var.project}-${var.environment}-app-${count.index + 1}-nic"
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.private_subnet_ids[count.index % length(var.private_subnet_ids)]
    private_ip_address_allocation = "Dynamic"
    # No public IP — outbound via NAT Gateway only.
  }

  tags = var.common_tags
}

# Associate NIC with NSG
resource "azurerm_network_interface_security_group_association" "app" {
  count = var.instance_count

  network_interface_id      = azurerm_network_interface.app[count.index].id
  network_security_group_id = var.nsg_id
}
