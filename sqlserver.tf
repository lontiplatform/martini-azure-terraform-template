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

  name                = "${local.name_prefix}-sql-server"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  count               = var.enable_sql_server ? 1 : 0

  server_version               = var.sql_server_version
  administrator_login          = azurerm_key_vault_secret.sql_admin_username.value
  administrator_login_password = azurerm_key_vault_secret.sql_admin_password.value
  databases                    = local.databases

  tags = merge(
    var.tags, {
      "Service" = "SQLServer"
    }
  )
}