module "virtual_network" {
  count = local.byo_vnet ? 0 : 1

  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "~> 0.9.3"

  name                = "${local.name_prefix}-vnet"
  address_space       = var.vnet_address_space
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  subnets = merge(
    {
      for i, cidr in var.public_subnet_cidrs :
      "public_subnet${i + 1}" => {
        name                            = "${local.name_prefix}-public-subnet-${i + 1}"
        address_prefixes                = [cidr]
        default_outbound_access_enabled = true
        network_security_group = {
          id = module.network_sg[0].resource_id
        }
        route_table = {
          id = module.route_table[0].resource_id
        }
      }
    },
    {
      for i, cidr in var.private_subnet_cidrs :
      "private_subnet${i + 1}" => {
        name              = "${local.name_prefix}-private-subnet-${i + 1}"
        address_prefixes  = [cidr]
        service_endpoints = ["Microsoft.KeyVault"]
        delegation = [{
          name = "aciDelegation"
          service_delegation = {
            name    = "Microsoft.ContainerInstance/containerGroups"
            actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
          }
        }]
        nat_gateway = {
          id = module.nat_gw[0].resource_id
        }
      }
    },
    var.enable_cassandra_tracker ? {
      cassandra_subnet = {
        name             = "${local.name_prefix}-cassandra-subnet"
        address_prefixes = [var.cassandra_subnet_cidr]
        delegation = [{
          name = "cassandraDelegation"
          service_delegation = {
            name    = "Microsoft.DocumentDB/cassandraClusters"
            actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
          }
        }]
        nat_gateway = {
          id = module.nat_gw[0].resource_id
        }
      }
    } : {}
  )

  tags = var.tags
}

module "route_table" {
  count = local.byo_vnet ? 0 : 1

  source  = "Azure/avm-res-network-routetable/azurerm"
  version = "~> 0.4.1"

  name                = "${local.name_prefix}-public-route-table"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  routes = {
    internet_route = {
      name           = "${local.name_prefix}-internet-route"
      address_prefix = "0.0.0.0/0"
      next_hop_type  = "Internet"
    }
  }

  tags = var.tags
}

module "nat_gw" {
  count = local.byo_vnet ? 0 : 1

  source  = "Azure/avm-res-network-natgateway/azurerm"
  version = "~> 0.2.1"

  name                = "${local.name_prefix}-nat-gw"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name


  public_ips = {
    public_ip_1 = {
      name = "${local.name_prefix}-nat-gw-public-ip"
    }
  }

  tags = var.tags
}

module "network_sg" {
  count = local.byo_vnet ? 0 : 1

  source  = "Azure/avm-res-network-networksecuritygroup/azurerm"
  version = "~> 0.5.0"

  name                = "${local.name_prefix}-network-sg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rules = local.nsg_rules

  tags = var.tags
}

# Mode B (existing_vnet != null): look up the caller's VNet so we can place
# our workload subnets into it. The data block is count-guarded so it stays
# inert in Mode A.
data "azurerm_virtual_network" "existing" {
  count = local.byo_vnet ? 1 : 0

  name                = var.existing_vnet.name
  resource_group_name = var.existing_vnet.resource_group_name
}

resource "azurerm_subnet" "aci" {
  count = local.byo_vnet ? 1 : 0

  name                 = "${local.name_prefix}-aci"
  resource_group_name  = var.existing_vnet.resource_group_name
  virtual_network_name = data.azurerm_virtual_network.existing[0].name
  address_prefixes     = [var.aci_subnet_cidr]

  delegation {
    name = "aciDelegation"
    service_delegation {
      name    = "Microsoft.ContainerInstance/containerGroups"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }

  lifecycle {
    precondition {
      condition     = var.aci_subnet_cidr != null
      error_message = "aci_subnet_cidr must be set when existing_vnet is non-null."
    }
  }
}

resource "azurerm_subnet" "appgw" {
  count = local.byo_vnet ? 1 : 0

  name                 = "${local.name_prefix}-appgw"
  resource_group_name  = var.existing_vnet.resource_group_name
  virtual_network_name = data.azurerm_virtual_network.existing[0].name
  address_prefixes     = [var.appgw_subnet_cidr]

  lifecycle {
    precondition {
      condition     = var.appgw_subnet_cidr != null
      error_message = "appgw_subnet_cidr must be set when existing_vnet is non-null."
    }
  }
}

resource "azurerm_subnet" "cassandra" {
  count = local.byo_vnet && var.enable_cassandra_tracker ? 1 : 0

  name                 = "${local.name_prefix}-cassandra"
  resource_group_name  = var.existing_vnet.resource_group_name
  virtual_network_name = data.azurerm_virtual_network.existing[0].name
  address_prefixes     = [var.cassandra_subnet_cidr]

  delegation {
    name = "cassandraDelegation"
    service_delegation {
      name    = "Microsoft.DocumentDB/cassandraClusters"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }

  lifecycle {
    precondition {
      condition     = var.cassandra_subnet_cidr != null
      error_message = "cassandra_subnet_cidr must be set when existing_vnet is non-null and enable_cassandra_tracker is true."
    }
  }
}

# Mode B: AppGW v2 requires GatewayManager 65200-65535 inbound and a 443
# listener path. In Mode A these rules are carried by module.network_sg
# attached to the public subnets; in Mode B no shared NSG is created, so we
# create a dedicated one and attach it only to the AppGW subnet.
resource "azurerm_network_security_group" "appgw" {
  count = local.byo_vnet ? 1 : 0

  name                = "${local.name_prefix}-appgw-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "AllowAppGatewayInfraPorts"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "65200-65535"
    source_address_prefix      = "GatewayManager"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowClientToAppGateway"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = var.appgw_subnet_cidr
  }

  tags = var.tags
}

resource "azurerm_subnet_network_security_group_association" "appgw" {
  count = local.byo_vnet ? 1 : 0

  subnet_id                 = azurerm_subnet.appgw[0].id
  network_security_group_id = azurerm_network_security_group.appgw[0].id
}

resource "azurerm_subnet_route_table_association" "aci" {
  count = local.byo_vnet && var.byo_vnet_route_table_id != null ? 1 : 0

  subnet_id      = azurerm_subnet.aci[0].id
  route_table_id = var.byo_vnet_route_table_id
}

resource "azurerm_subnet_network_security_group_association" "aci" {
  count = local.byo_vnet && var.byo_vnet_workload_nsg_id != null ? 1 : 0

  subnet_id                 = azurerm_subnet.aci[0].id
  network_security_group_id = var.byo_vnet_workload_nsg_id
}

resource "azurerm_subnet_route_table_association" "cassandra" {
  count = local.byo_vnet && var.enable_cassandra_tracker && var.byo_vnet_route_table_id != null ? 1 : 0

  subnet_id      = azurerm_subnet.cassandra[0].id
  route_table_id = var.byo_vnet_route_table_id
}

resource "azurerm_subnet_network_security_group_association" "cassandra" {
  count = local.byo_vnet && var.enable_cassandra_tracker && var.byo_vnet_workload_nsg_id != null ? 1 : 0

  subnet_id                 = azurerm_subnet.cassandra[0].id
  network_security_group_id = var.byo_vnet_workload_nsg_id
}