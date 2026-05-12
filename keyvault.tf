resource "random_string" "kv_suffix" {
  length  = 6
  upper   = false
  special = false
  numeric = true
}

resource "azurerm_key_vault" "key_vault" {
  #checkov:skip=CKV_AZURE_42:Purge protection is not required for this template
  #checkov:skip=CKV_AZURE_110:Purge protection is not required for this template
  #checkov:skip=CKV2_AZURE_32:No need for private endpoint yet
  #checkov:skip=CKV_AZURE_109:Firewall does not provide flexibility to NAT template users
  #checkov:skip=CKV_AZURE_189:Buildtime requires public access to key vault
  name                            = substr("${replace(local.name_prefix_slug, "-", "")}kv${random_string.kv_suffix.result}", 0, 24)
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

resource "azurerm_key_vault_secret" "cassandra_admin_password" {
  #checkov:skip=CKV_AZURE_41:Skipping secret expiration
  count = var.enable_cassandra_tracker ? 1 : 0

  name         = "cassandra-admin-password"
  value        = random_password.cassandra_admin[0].result
  key_vault_id = azurerm_key_vault.key_vault.id
  content_type = "secret"

  tags = var.tags
}

resource "azurerm_key_vault_secret" "cassandra_contact_point" {
  count = var.enable_cassandra_tracker ? 1 : 0

  name         = "cassandra-contact-point"
  value        = local.cassandra_node_fqdns[0]
  key_vault_id = azurerm_key_vault.key_vault.id
  content_type = "text/plain"

  tags = var.tags
}

resource "azurerm_key_vault_secret" "event_hub_namespace_fqdn" {
  count = var.enable_event_hub ? 1 : 0

  name         = "event-hub-namespace-fqdn"
  value        = "${azurerm_eventhub_namespace.this[0].name}.servicebus.windows.net"
  key_vault_id = azurerm_key_vault.key_vault.id
  content_type = "text/plain"

  tags = var.tags
}

resource "azurerm_key_vault_secret" "event_hub_names" {
  count = var.enable_event_hub ? 1 : 0

  name         = "event-hub-names"
  value        = join(",", sort([for h in azurerm_eventhub.this : h.name]))
  key_vault_id = azurerm_key_vault.key_vault.id
  content_type = "text/plain"

  tags = var.tags
}