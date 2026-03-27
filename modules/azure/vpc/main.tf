# modules/azure/vpc/main.tf
#
# Azure networking: Resource Group, VNet, subnets, NAT Gateway, Network Watcher flow logs.
#
# Azure terminology mapping (for your reference):
#   AWS VPC            → Azure Virtual Network (VNet)
#   AWS Subnet         → Azure Subnet
#   AWS Security Group → Azure Network Security Group (NSG) — in the security module
#   AWS NAT Gateway    → Azure NAT Gateway
#   AWS IGW            → Azure has no explicit IGW; public IPs handle inbound
#   AWS IAM Role       → Azure Managed Identity
#   AWS CloudWatch     → Azure Monitor / Log Analytics
#   AWS Flow Logs      → Azure Network Watcher Flow Logs

resource "azurerm_resource_group" "this" {
  name     = "${var.project}-${var.environment}-rg"
  location = var.location

  tags = merge(var.common_tags, {
    Project     = var.project
    Environment = var.environment
  })
}

# --- Virtual Network ----------------------------------------------------------

resource "azurerm_virtual_network" "this" {
  name                = "${var.project}-${var.environment}-vnet"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = [var.vnet_cidr]

  tags = var.common_tags
}

# --- Subnets ------------------------------------------------------------------
# Azure subnets require a delegated service for some PaaS services.
# For plain VMs, no delegation is needed.

resource "azurerm_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  name                 = "${var.project}-${var.environment}-public-${count.index}"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.public_subnet_cidrs[count.index]]
}

resource "azurerm_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  name                 = "${var.project}-${var.environment}-private-${count.index}"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.private_subnet_cidrs[count.index]]
}

# --- NAT Gateway --------------------------------------------------------------
# Azure NAT Gateway provides outbound connectivity for private subnets.
# One NAT Gateway with one public IP covers all private subnets.

resource "azurerm_public_ip" "nat" {
  name                = "${var.project}-${var.environment}-nat-pip"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = var.common_tags
}

resource "azurerm_nat_gateway" "this" {
  name                    = "${var.project}-${var.environment}-nat"
  location                = azurerm_resource_group.this.location
  resource_group_name     = azurerm_resource_group.this.name
  sku_name                = "Standard"
  idle_timeout_in_minutes = 10

  tags = var.common_tags
}

resource "azurerm_nat_gateway_public_ip_association" "this" {
  nat_gateway_id       = azurerm_nat_gateway.this.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

resource "azurerm_subnet_nat_gateway_association" "private" {
  count = length(azurerm_subnet.private)

  subnet_id      = azurerm_subnet.private[count.index].id
  nat_gateway_id = azurerm_nat_gateway.this.id
}

# --- Network Watcher Flow Logs ------------------------------------------------
# Azure Network Watcher must exist in the same region.
# A default one is created automatically per region, but we declare it explicitly
# for Terraform to manage it cleanly.

resource "azurerm_network_watcher" "this" {
  name                = "${var.project}-${var.environment}-nw"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  tags = var.common_tags
}

resource "azurerm_storage_account" "flow_logs" {
  name                     = lower(replace("${var.project}${var.environment}flowlogs", "-", ""))
  resource_group_name      = azurerm_resource_group.this.name
  location                 = azurerm_resource_group.this.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  tags = var.common_tags
}
