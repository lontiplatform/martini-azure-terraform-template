resource "azurerm_key_vault" "key_vault" {
  #checkov:skip=CKV_AZURE_42:Purge protection is not required for this template
  #checkov:skip=CKV_AZURE_110:Purge protection is not required for this template
  #checkov:skip=CKV2_AZURE_32:No need for private endpoint yet
  #checkov:skip=CKV_AZURE_109:Firewall does not provide flexibility to NAT template users
  #checkov:skip=CKV_AZURE_189:Buildtime requires public access to key vault
  name                            = "${local.name_prefix}-kv"
  location                        = azurerm_resource_group.rg.location
  resource_group_name             = azurerm_resource_group.rg.name
  enabled_for_disk_encryption     = true
  enabled_for_deployment          = true
  enabled_for_template_deployment = true
  tenant_id                       = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days      = 7
  purge_protection_enabled        = false

  sku_name = "standard"

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    secret_permissions = ["Get", "List", "Set", "Delete", "Purge", "Recover"]
  }

  tags = var.tags
}

resource "azurerm_key_vault_secret" "martini_workspace_license" {
  #checkov:skip=CKV_AZURE_41:Skipping license expiration
  name         = "martini-workspace-license"
  value        = var.martini_workspace_license
  key_vault_id = azurerm_key_vault.key_vault.id
  content_type = "secret"

  tags = var.tags
}

resource "azurerm_key_vault_secret" "sql_admin_password" {
  #checkov:skip=CKV_AZURE_41:Skipping secret expiration
  name         = "sql-admin-password"
  value        = random_password.admin_password.result
  key_vault_id = azurerm_key_vault.key_vault.id
  content_type = "secret"

  tags = var.tags
}

resource "azurerm_key_vault_secret" "sql_admin_username" {
  #checkov:skip=CKV_AZURE_41:Skipping secret expiration
  name         = "sql-admin-username"
  value        = var.sql_server_admin_username
  key_vault_id = azurerm_key_vault.key_vault.id
  content_type = "username"

  tags = var.tags
}