module "virtual_network" {
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
          id = module.network_sg.resource_id
        }
        route_table = {
          id = module.route_table.resource_id
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
          id = module.nat_gw.resource_id
        }
      }
    }
  )

  tags = var.tags
}

module "route_table" {
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
  source  = "Azure/avm-res-network-networksecuritygroup/azurerm"
  version = "~> 0.5.0"

  name                = "${local.name_prefix}-network-sg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rules = local.nsg_rules

  tags = var.tags
}