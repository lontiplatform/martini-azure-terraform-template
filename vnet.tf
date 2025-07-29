module "virtual_network" {
  #checkov:skip=CKV_TF_1:Module version is used instead of hash
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "~> 0.9.3"

  name                = "${local.name_prefix}-vnet"
  address_space       = ["10.0.0.0/18"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  subnets = {
    "public_subnet1" = {
      name                            = "${local.name_prefix}-public-subnet-1"
      address_prefixes                = ["10.0.1.0/24"]
      default_outbound_access_enabled = true
      network_security_group = {
        id = module.network_sg.resource_id
      }
    }
    "public_subnet2" = {
      name                            = "${local.name_prefix}-public-subnet-2"
      address_prefixes                = ["10.0.2.0/24"]
      default_outbound_access_enabled = true
      network_security_group = {
        id = module.network_sg.resource_id
      }
    }
    "private_subnet1" = {
      name             = "${local.name_prefix}-private-subnet-1"
      address_prefixes = ["10.0.11.0/24"]
    }
    "private_subnet2" = {
      name             = "${local.name_prefix}-private-subnet-2"
      address_prefixes = ["10.0.12.0/24"]
    }
  }

  tags = var.tags
}

module "route_table" {
  #checkov:skip=CKV_TF_1:Module version is used instead of hash
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

  subnet_resource_ids = {
    public_subnet1 = local.public_subnet1_id
    public_subnet2 = local.public_subnet2_id
  }

  tags = var.tags
}

module "nat_gw" {
  #checkov:skip=CKV_TF_1:Module version is used instead of hash
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

  subnet_associations = {
    subnet_1 = {
      resource_id = local.private_subnet1_id
    },
    subnet_2 = {
      resource_id = local.private_subnet2_id
    }
  }

  tags = var.tags
}

module "network_sg" {
  #checkov:skip=CKV_TF_1:Module version is used instead of hash
  source  = "Azure/avm-res-network-networksecuritygroup/azurerm"
  version = "~> 0.5.0"

  name                = "${local.name_prefix}-network-sg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rules = local.nsg_rules

  tags = var.tags
}