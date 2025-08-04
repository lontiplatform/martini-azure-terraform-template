locals {
  public_subnet1_id  = module.virtual_network.subnets["public_subnet1"].resource.id
  public_subnet2_id  = module.virtual_network.subnets["public_subnet2"].resource.id
  private_subnet1_id = module.virtual_network.subnets["private_subnet1"].resource.id
  private_subnet2_id = module.virtual_network.subnets["private_subnet2"].resource.id

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
      destination_address_prefix = "10.0.1.0/24"
      destination_port_ranges    = ["80"]
    }

    "AllowAppGatewayToBackend" = {
      name                       = "AllowAppGatewayToBackend"
      access                     = "Allow"
      direction                  = "Inbound"
      priority                   = 130
      protocol                   = "Tcp"
      source_address_prefix      = "10.0.1.0/24"
      source_port_range          = "*"
      destination_address_prefix = "10.0.11.0/24"
      destination_port_ranges    = ["8080"]
    }


  }

  name_prefix                = "${terraform.workspace}-martini${var.name_suffix}"
  aci_service_name           = "${local.name_prefix}-service"
  aci_container_port         = 8080
  jdbc_postgres_download_url = "https://github.com/pgjdbc/pgjdbc/releases/download/REL${var.martini_workspace_postgres_driver_version}/postgresql-${var.martini_workspace_postgres_driver_version}.jar"
  jdbc_mysql_download_url    = "https://repo1.maven.org/maven2/com/mysql/mysql-connector-j/${var.martini_workspace_mysql_driver_version}/mysql-connector-j-${var.martini_workspace_mysql_driver_version}.jar"
}