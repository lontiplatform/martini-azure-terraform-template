locals {
  private_subnet_ids = [
    for k, v in module.virtual_network.subnets : v.resource.id
    if startswith(k, "private_subnet")
  ]

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
      destination_address_prefix = module.virtual_network.subnets["public_subnet1"].resource.body.properties.addressPrefixes[0]
      destination_port_ranges    = ["80"]
    }

    "AllowAppGatewayToBackend" = {
      name                         = "AllowAppGatewayToBackend"
      access                       = "Allow"
      direction                    = "Inbound"
      priority                     = 130
      protocol                     = "Tcp"
      source_address_prefix        = module.virtual_network.subnets["public_subnet1"].resource.body.properties.addressPrefixes[0]
      source_port_range            = "*"
      destination_address_prefixes = var.private_subnet_cidrs
      destination_port_ranges      = [tostring(local.aci_container_port)]
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

  tracker_dbxml_rendered = var.enable_cassandra_tracker ? templatefile("${path.module}/templates/tracker.dbxml.tftpl", {
    contact_point = "${azurerm_cosmosdb_account.cassandra[0].name}.cassandra.cosmos.azure.com"
    port          = 10350
    username      = azurerm_cosmosdb_account.cassandra[0].name
    password      = azurerm_cosmosdb_account.cassandra[0].primary_key
    ssl           = "true"
  }) : ""
}