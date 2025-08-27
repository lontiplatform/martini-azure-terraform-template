locals {
  public_subnet1_id    = module.virtual_network.subnets["public_subnet1"].resource.id
  private_subnet1_id   = module.virtual_network.subnets["private_subnet1"].resource.id
  private_subnet2_id   = module.virtual_network.subnets["private_subnet2"].resource.id
  public_subnet1_cidr  = module.virtual_network.subnets["public_subnet1"].resource.body.properties.addressPrefixes[0]
  public_subnet2_cidr  = module.virtual_network.subnets["public_subnet2"].resource.body.properties.addressPrefixes[0]
  private_subnet1_cidr = module.virtual_network.subnets["private_subnet1"].resource.body.properties.addressPrefixes[0]
  private_subnet2_cidr = module.virtual_network.subnets["private_subnet2"].resource.body.properties.addressPrefixes[0]

  nsg_rules = {
    "AllowInternetOut" = {
      name                       = "AllowInternetOut"
      access                     = "Allow"
      destination_address_prefix = "*"
      destination_port_range     = "*"
      direction                  = "Outbound"
      priority                   = 200
      protocol                   = "*"
      source_address_prefix      = "*"
      source_port_range          = "*"
    }

    "AllowAppGatewayInfraPorts" = {
      name                       = "AllowAppGatewayInfraPorts"
      access                     = "Allow"
      direction                  = "Inbound"
      priority                   = 100
      protocol                   = "Tcp"
      source_address_prefix      = "GatewayManager"
      source_port_range          = "*"
      destination_address_prefix = "*"
      destination_port_ranges    = ["65200-65535"]
    }

    "AllowClientToAppGateway" = {
      name                       = "AllowClientToAppGateway"
      access                     = "Allow"
      direction                  = "Inbound"
      priority                   = 120
      protocol                   = "Tcp"
      source_address_prefix      = "*"
      source_port_range          = "*"
      destination_address_prefix = local.public_subnet1_cidr
      destination_port_ranges    = ["80"]
    }

    "AllowAppGatewayToBackend" = {
      name                       = "AllowAppGatewayToBackend"
      access                     = "Allow"
      direction                  = "Inbound"
      priority                   = 130
      protocol                   = "Tcp"
      source_address_prefix      = local.public_subnet1_cidr
      source_port_range          = "*"
      destination_address_prefix = local.private_subnet1_cidr
      destination_port_ranges    = ["${local.aci_container_port}"]
    }


  }

  databases = {
    martini = {
      name        = var.sql_database_name
      max_size_gb = var.max_size_gb
      sku_name    = "S0"

      tags = var.tags

    }
  }

  name_prefix        = "${terraform.workspace}-martini${var.name_suffix}"
  aci_service_name   = "${local.name_prefix}-service"
  aci_container_port = 8080
}