# modules/azure/security/main.tf
#
# Azure NSG (Network Security Group) + User-Assigned Managed Identity.
# NSGs are attached to subnets and/or NICs.
# Managed Identity = Azure equivalent of AWS IAM Instance Profile.

resource "azurerm_network_security_group" "app" {
  name                = "${var.project}-${var.environment}-app-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name

  security_rule {
    name                       = "allow-https-inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefixes    = var.allowed_ingress_cidrs
    destination_address_prefix = "*"
    description                = "Allow HTTPS from permitted CIDRs."
  }

  security_rule {
    name                       = "allow-http-inbound"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefixes    = var.allowed_ingress_cidrs
    destination_address_prefix = "*"
    description                = "Allow HTTP (redirect to HTTPS at app layer)."
  }

  security_rule {
    name                       = "deny-all-inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
    description                = "Explicit deny-all at bottom of rule list."
  }

  tags = var.common_tags
}

# Associate NSG with all private subnets
resource "azurerm_subnet_network_security_group_association" "private" {
  count = length(var.private_subnet_ids)

  subnet_id                 = var.private_subnet_ids[count.index]
  network_security_group_id = azurerm_network_security_group.app.id
}

# --- SSH via Azure Bastion (optional) -----------------------------------------
# Azure Bastion is the managed equivalent of a bastion host.
# It provides browser-based SSH/RDP without exposing port 22 publicly.
# Requires a dedicated AzureBastionSubnet (name is fixed, cannot be changed).

resource "azurerm_subnet" "bastion" {
  count = var.enable_bastion ? 1 : 0

  # This name is required by Azure — do not change it.
  name                 = "AzureBastionSubnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = var.vnet_name
  address_prefixes     = [var.bastion_subnet_cidr]
}

resource "azurerm_public_ip" "bastion" {
  count = var.enable_bastion ? 1 : 0

  name                = "${var.project}-${var.environment}-bastion-pip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = var.common_tags
}

resource "azurerm_bastion_host" "this" {
  count = var.enable_bastion ? 1 : 0

  name                = "${var.project}-${var.environment}-bastion"
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.bastion[0].id
    public_ip_address_id = azurerm_public_ip.bastion[0].id
  }

  tags = var.common_tags
}

# --- User-Assigned Managed Identity -------------------------------------------
# Attach to VMs to allow them to authenticate to Azure services without credentials.

resource "azurerm_user_assigned_identity" "app" {
  name                = "${var.project}-${var.environment}-app-identity"
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = var.common_tags
}

# Grant identity access to write logs (Monitoring Metrics Publisher)
resource "azurerm_role_assignment" "monitoring" {
  scope                = "/subscriptions/${var.subscription_id}"
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
}
