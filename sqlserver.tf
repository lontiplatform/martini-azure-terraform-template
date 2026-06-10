resource "random_password" "admin_password" {
  length           = 16
  override_special = "!#$%&*()-_=+[]{}<>:?"
  special          = true
}

module "sql_server" {
  #checkov:skip=CKV_AZURE_23:Auditing is currently not required for this template
  #checkov:skip=CKV_AZURE_24:Auditing is currently not required for this template
  #checkov:skip=CKV2_AZURE_2:Vulnerability Assessment is currently not required for this template
  source  = "Azure/avm-res-sql-server/azurerm"
  version = "~> 0.1.5"

  name                = "${substr(local.name_prefix_slug, 0, 52)}-sql-server"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  count               = var.enable_sql_server ? 1 : 0

  server_version               = var.sql_server_version
  administrator_login          = azurerm_key_vault_secret.sql_admin_username.value
  administrator_login_password = azurerm_key_vault_secret.sql_admin_password.value
  databases                    = local.databases

  public_network_access_enabled = true

  # System-assigned managed identity backs the local-SQL fallback for the
  # `Azure Event Hubs Data Sender` grant when `enable_event_hub = true` and
  # `ces_source_sql_server` is not set. Harmless when CES is not in use.
  managed_identities = {
    system_assigned = true
  }

  tags = merge(
    var.tags, {
      "Service" = "SQLServer"
    }
  )
}

data "azurerm_public_ip" "nat_gw" {
  count = var.enable_sql_server && !local.byo_vnet ? 1 : 0

  name                = "${local.name_prefix}-nat-gw-public-ip"
  resource_group_name = azurerm_resource_group.rg.name

  depends_on = [module.nat_gw]
}

resource "azurerm_mssql_firewall_rule" "martini_egress" {
  count = var.enable_sql_server ? 1 : 0

  name             = "martini-egress"
  server_id        = module.sql_server[0].resource.id
  start_ip_address = local.martini_egress_ip
  end_ip_address   = local.martini_egress_ip
}