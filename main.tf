locals {
  byo_vnet = var.existing_vnet != null

  private_subnet_ids = local.byo_vnet ? [] : [
    for k, v in module.virtual_network[0].subnets : v.resource.id
    if startswith(k, "private_subnet")
  ]

  aci_subnet_ids = local.byo_vnet ? [azurerm_subnet.aci[0].id] : local.private_subnet_ids

  aca_subnet_id = local.byo_vnet ? azurerm_subnet.aca[0].id : module.virtual_network[0].subnets["aca_subnet"].resource.id

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
      destination_port_ranges    = ["80", "443"]
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

  name_prefix = "${terraform.workspace}-martini${var.name_suffix}"
  name_prefix_slug = trim(
    replace(
      replace(lower(local.name_prefix), "/[^a-z0-9-]/", "-"),
      "/-+/", "-"
    ),
    "-"
  )

  aci_service_name   = "${local.name_prefix}-service"
  aci_container_port = 8080
  designer_ui_port   = 3000

  aci_docker_image_url = (
    var.enable_designer && var.ecr_source_credentials != null
    ? "${azurerm_container_registry.ecr_mirror[0].login_server}/lontiplatform/martini-designer-online"
    : (var.enable_designer ? "lontiplatform/martini-designer-online" : "lontiplatform/martini-server-runtime")
  )

  designer_registry_credential = (
    var.enable_designer && var.ecr_source_credentials != null
    ? {
      server   = azurerm_container_registry.ecr_mirror[0].login_server
      username = azurerm_container_registry_token.aci_designer_pull[0].name
      password = azurerm_container_registry_token_password.aci_designer_pull[0].password1[0].value
    }
    : (var.docker_registry_username != "" ? {
      server   = "index.docker.io"
      username = var.docker_registry_username
      password = var.docker_registry_password
    } : null)
  )

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

  # ACS data_location is a curated residency label, not an Azure region.
  acs_data_location_by_region = {
    eastus             = "United States"
    eastus2            = "United States"
    centralus          = "United States"
    northcentralus     = "United States"
    southcentralus     = "United States"
    westus             = "United States"
    westus2            = "United States"
    westus3            = "United States"
    westcentralus      = "United States"
    canadacentral      = "Canada"
    canadaeast         = "Canada"
    brazilsouth        = "Brazil"
    northeurope        = "Europe"
    westeurope         = "Europe"
    swedencentral      = "Europe"
    swedensouth        = "Europe"
    francecentral      = "France"
    francesouth        = "France"
    germanywestcentral = "Germany"
    germanynorth       = "Germany"
    norwayeast         = "Norway"
    norwaywest         = "Norway"
    switzerlandnorth   = "Switzerland"
    switzerlandwest    = "Switzerland"
    uksouth            = "UK"
    ukwest             = "UK"
    uaenorth           = "UAE"
    uaecentral         = "UAE"
    australiaeast      = "Australia"
    australiasoutheast = "Australia"
    australiacentral   = "Australia"
    australiacentral2  = "Australia"
    southeastasia      = "Asia Pacific"
    eastasia           = "Asia Pacific"
    japaneast          = "Japan"
    japanwest          = "Japan"
    koreacentral       = "Korea"
    koreasouth         = "Korea"
    centralindia       = "India"
    southindia         = "India"
    westindia          = "India"
    southafricanorth   = "Africa"
    southafricawest    = "Africa"
    usgovvirginia      = "usgov"
    usgovarizona       = "usgov"
    usgovtexas         = "usgov"
  }

  acs_data_location = lookup(local.acs_data_location_by_region, lower(var.rg_location), "United States")
}