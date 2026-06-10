resource "random_string" "storage_suffix" {
  length  = 6
  upper   = false
  special = false
  numeric = true
}

resource "azurerm_storage_account" "conf" {
  #checkov:skip=CKV_AZURE_33:Storage logging not required for this template
  #checkov:skip=CKV_AZURE_59:Demo template: public access is intentional so Terraform can upload the seed tracker.dbxml from any developer/CI machine. Switch to Deny + allow-list for production.
  #checkov:skip=CKV_AZURE_206:LRS is sufficient for this template
  #checkov:skip=CKV2_AZURE_1:Encryption keys managed by Microsoft is sufficient for this template
  #checkov:skip=CKV2_AZURE_18:Customer-managed keys not required for this template
  #checkov:skip=CKV2_AZURE_33:Private endpoint not required for this template
  #checkov:skip=CKV2_AZURE_38:Soft-delete defaults are sufficient for this template
  #checkov:skip=CKV2_AZURE_40:Shared access keys required for ACI Azure Files volume mount
  #checkov:skip=CKV2_AZURE_41:SAS tokens not used; access is via account key from ACI
  #checkov:skip=CKV2_AZURE_47:Account hosts only the Azure Files share mounted by ACI; no blobs are created so anonymous blob access is inapplicable.
  #checkov:skip=CKV_AZURE_190:Account hosts only the Azure Files share mounted by ACI; no blob containers are created so blob public-access policy is inapplicable.
  name                = substr("${replace(local.name_prefix_slug, "-", "")}conf${random_string.storage_suffix.result}", 0, 24)
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  account_kind              = "FileStorage"
  account_tier              = "Premium"
  account_replication_type  = "LRS"
  min_tls_version           = "TLS1_2"
  shared_access_key_enabled = true

  public_network_access_enabled = true

  tags = var.tags
}

resource "azurerm_storage_share" "db_pool" {
  name               = "db-pool"
  storage_account_id = azurerm_storage_account.conf.id
  quota              = var.martini_premium_share_quota_gb
  access_tier        = "Premium"
}

resource "azurerm_storage_share" "runtime_lib_ext" {
  count = var.enable_designer ? 0 : 1

  name               = "runtime-lib-ext"
  storage_account_id = azurerm_storage_account.conf.id
  quota              = var.martini_premium_share_quota_gb
  access_tier        = "Premium"
}

resource "azurerm_storage_share" "runtime_conf_overrides" {
  count = var.enable_designer ? 0 : 1

  name               = "runtime-conf-overrides"
  storage_account_id = azurerm_storage_account.conf.id
  quota              = var.martini_premium_share_quota_gb
  access_tier        = "Premium"
}

resource "azurerm_storage_share" "runtime_packages" {
  count = var.enable_designer ? 0 : 1

  name               = "runtime-packages"
  storage_account_id = azurerm_storage_account.conf.id
  quota              = var.martini_premium_share_quota_gb
  access_tier        = "Premium"
}

resource "local_file" "tracker_dbxml" {
  count = var.enable_cassandra_tracker ? 1 : 0

  filename        = "${path.module}/.generated/tracker.dbxml"
  content         = local.tracker_dbxml_rendered
  file_permission = "0644"
}

resource "azurerm_storage_share_file" "tracker_dbxml" {
  count = var.enable_cassandra_tracker ? 1 : 0

  name              = "tracker.dbxml"
  storage_share_url = azurerm_storage_share.db_pool.url
  source            = local_file.tracker_dbxml[0].filename
  content_md5       = local_file.tracker_dbxml[0].content_md5
}

resource "local_file" "sqlserver_dbxml" {
  count = var.enable_sql_server ? 1 : 0

  filename        = "${path.module}/.generated/${var.sql_database_name}.dbxml"
  content         = local.sqlserver_dbxml_rendered
  file_permission = "0644"
}

resource "azurerm_storage_share_file" "sqlserver_dbxml" {
  count = var.enable_sql_server ? 1 : 0

  name              = "${var.sql_database_name}.dbxml"
  storage_share_url = azurerm_storage_share.db_pool.url
  source            = local_file.sqlserver_dbxml[0].filename
  content_md5       = local_file.sqlserver_dbxml[0].content_md5
}

resource "azurerm_storage_share" "designer_workspace_data" {
  count = var.enable_designer ? 1 : 0

  name               = "designer-workspace-data"
  storage_account_id = azurerm_storage_account.conf.id
  quota              = var.martini_premium_share_quota_gb
  access_tier        = "Premium"
}

resource "azurerm_storage_share" "designer_workspace_user" {
  count = var.enable_designer ? 1 : 0

  name               = "designer-workspace-user"
  storage_account_id = azurerm_storage_account.conf.id
  quota              = var.martini_premium_share_quota_gb
  access_tier        = "Premium"
}

resource "azurerm_storage_share_directory" "designer_runtime_conf" {
  count = var.enable_designer && (var.enable_cassandra_tracker || var.enable_sql_server) ? 1 : 0

  name              = "conf"
  storage_share_url = azurerm_storage_share.designer_workspace_data[0].url
}

resource "azurerm_storage_share_directory" "designer_runtime_db_pool" {
  count = var.enable_designer && (var.enable_cassandra_tracker || var.enable_sql_server) ? 1 : 0

  name              = "conf/db-pool"
  storage_share_url = azurerm_storage_share.designer_workspace_data[0].url

  depends_on = [azurerm_storage_share_directory.designer_runtime_conf]
}

resource "azurerm_storage_share_file" "designer_tracker_dbxml" {
  count = var.enable_designer && var.enable_cassandra_tracker ? 1 : 0

  name              = "tracker.dbxml"
  path              = "conf/db-pool"
  storage_share_url = azurerm_storage_share.designer_workspace_data[0].url
  source            = local_file.tracker_dbxml[0].filename
  content_md5       = local_file.tracker_dbxml[0].content_md5

  depends_on = [azurerm_storage_share_directory.designer_runtime_db_pool]
}

resource "azurerm_storage_share_file" "designer_sqlserver_dbxml" {
  count = var.enable_designer && var.enable_sql_server ? 1 : 0

  name              = "${var.sql_database_name}.dbxml"
  path              = "conf/db-pool"
  storage_share_url = azurerm_storage_share.designer_workspace_data[0].url
  source            = local_file.sqlserver_dbxml[0].filename
  content_md5       = local_file.sqlserver_dbxml[0].content_md5

  depends_on = [azurerm_storage_share_directory.designer_runtime_db_pool]
}

resource "local_file" "designer_version" {
  count = var.enable_designer ? 1 : 0

  filename        = "${path.module}/.generated/designer-version"
  content         = "0.0.0"
  file_permission = "0644"
}

resource "azurerm_storage_share_file" "designer_version" {
  count = var.enable_designer ? 1 : 0

  name              = ".version"
  storage_share_url = azurerm_storage_share.designer_workspace_data[0].url
  source            = local_file.designer_version[0].filename
  content_md5       = md5(local_file.designer_version[0].content)

  lifecycle {
    ignore_changes       = [source, content_md5]
    replace_triggered_by = [local_file.designer_version[0].content_sha1]
  }
}
