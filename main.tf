locals {
  byo_vnet = var.existing_vnet != null

  private_subnet_ids = local.byo_vnet ? [] : [
    for k, v in module.virtual_network[0].subnets : v.resource.id
    if startswith(k, "private_subnet")
  ]

  aci_subnet_ids = local.byo_vnet ? [azurerm_subnet.aci[0].id] : local.private_subnet_ids

  appgw_subnet_id = local.byo_vnet ? azurerm_subnet.appgw[0].id : module.virtual_network[0].subnets["public_subnet1"].resource.id

  appgw_subnet_cidr = local.byo_vnet ? var.appgw_subnet_cidr : module.virtual_network[0].subnets["public_subnet1"].resource.body.properties.addressPrefixes[0]

  cassandra_subnet_id = local.byo_vnet ? (var.enable_cassandra_tracker ? azurerm_subnet.cassandra[0].id : null) : (var.enable_cassandra_tracker ? module.virtual_network[0].subnets["cassandra_subnet"].resource.id : null)

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
      destination_address_prefix = local.appgw_subnet_cidr
      destination_port_ranges    = ["443"]
    }

    "AllowAppGatewayToBackend" = {
      name                         = "AllowAppGatewayToBackend"
      access                       = "Allow"
      direction                    = "Inbound"
      priority                     = 130
      protocol                     = "Tcp"
      source_address_prefix        = local.appgw_subnet_cidr
      source_port_range            = "*"
      destination_address_prefixes = var.private_subnet_cidrs
      destination_port_ranges      = [tostring(var.enable_designer ? local.designer_ui_port : local.aci_container_port)]
    }
  }

  databases = {
    martini = {
      name        = var.sql_database_name
      max_size_gb = var.sql_max_size_gb
      sku_name    = "S0"

      tags = var.tags

    }
  }

  name_prefix        = "${terraform.workspace}-martini${var.name_suffix}"
  aci_service_name   = "${local.name_prefix}-service"
  aci_container_port = 8080
  designer_ui_port   = 3000

  aci_docker_image_url = var.enable_designer ? "lontiplatform/martini-designer-online" : "lontiplatform/martini-server-runtime"

  # Azure Managed Cassandra issues node certificates with SANs for the FQDN
  # <dc-name>00000<n>.internal.cloudapp.net, not for the seed IP. The Datastax
  # driver's hostname verification fails on an IP contact point and reports the
  # SSL handshake error as an opaque NPE.
  cassandra_node_fqdns = var.enable_cassandra_tracker ? [
    for i in range(var.cassandra_node_count) :
    format("%s%06d.internal.cloudapp.net", azurerm_cosmosdb_cassandra_datacenter.tracker[0].name, i)
  ] : []

  tracker_dbxml_rendered = var.enable_cassandra_tracker ? templatefile("${path.module}/templates/cassandra_tracker.dbxml.tftpl", {
    contact_points = local.cassandra_node_fqdns
    port           = 9042
    username       = "cassandra"
    password       = random_password.cassandra_admin[0].result
    ssl            = "true"
  }) : ""
}