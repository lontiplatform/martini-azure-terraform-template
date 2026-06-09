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
    } : {},
    {
      aca_subnet = {
        name             = "${local.name_prefix}-aca-subnet"
        address_prefixes = [var.aca_subnet_cidr]
        delegation = [{
          name = "acaDelegation"
          service_delegation = {
            name    = "Microsoft.App/environments"
            actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
          }
        }]
        nat_gateway = {
          id = module.nat_gw[0].resource_id
        }
      }
    }
  )

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

resource "azurerm_subnet" "aca" {
  count = local.byo_vnet ? 1 : 0

  name                 = "${local.name_prefix}-aca"
  resource_group_name  = var.existing_vnet.resource_group_name
  virtual_network_name = data.azurerm_virtual_network.existing[0].name
  address_prefixes     = [var.aca_subnet_cidr]

  delegation {
    name = "acaDelegation"
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }

  lifecycle {
    precondition {
      condition     = var.aca_subnet_cidr != null
      error_message = "aca_subnet_cidr must be set when existing_vnet is non-null."
    }
  }
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

resource "azurerm_subnet_route_table_association" "aca" {
  count = local.byo_vnet ? 1 : 0

  subnet_id      = azurerm_subnet.aca[0].id
  route_table_id = azurerm_route_table.aca[0].id
}

resource "azurerm_subnet_network_security_group_association" "aca" {
  count = local.byo_vnet && var.byo_vnet_workload_nsg_id != null ? 1 : 0

  subnet_id                 = azurerm_subnet.aca[0].id
  network_security_group_id = var.byo_vnet_workload_nsg_id
}

resource "azurerm_route_table" "aca" {
  count = local.byo_vnet ? 1 : 0

  name                = "${local.name_prefix}-aca-rt"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  route {
    name           = "internet-direct"
    address_prefix = "0.0.0.0/0"
    next_hop_type  = "Internet"
  }

  tags = var.tags
}

resource "azurerm_public_ip" "aca_nat" {
  count = local.byo_vnet ? 1 : 0

  name                = "${local.name_prefix}-aca-nat-pip"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = var.tags
}

resource "azurerm_nat_gateway" "aca" {
  count = local.byo_vnet ? 1 : 0

  name                = "${local.name_prefix}-aca-nat"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku_name            = "Standard"

  tags = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "aca" {
  count = local.byo_vnet ? 1 : 0

  nat_gateway_id       = azurerm_nat_gateway.aca[0].id
  public_ip_address_id = azurerm_public_ip.aca_nat[0].id
}

resource "azurerm_subnet_nat_gateway_association" "aca" {
  count = local.byo_vnet ? 1 : 0

  subnet_id      = azurerm_subnet.aca[0].id
  nat_gateway_id = azurerm_nat_gateway.aca[0].id
}
