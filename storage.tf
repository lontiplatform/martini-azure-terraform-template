resource "random_string" "storage_suffix" {
  count = var.enable_cassandra_tracker ? 1 : 0

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
  count = var.enable_cassandra_tracker ? 1 : 0

  name                = substr("${replace(local.name_prefix, "-", "")}conf${random_string.storage_suffix[0].result}", 0, 24)
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  account_tier              = "Standard"
  account_replication_type  = "LRS"
  min_tls_version           = "TLS1_2"
  shared_access_key_enabled = true

  public_network_access_enabled = true

  tags = var.tags
}

resource "azurerm_storage_share" "conf_db_pool" {
  count = var.enable_cassandra_tracker ? 1 : 0

  name               = "conf-db-pool"
  storage_account_id = azurerm_storage_account.conf[0].id
  quota              = 1
}

resource "local_file" "tracker_dbxml" {
  count = var.enable_cassandra_tracker ? 1 : 0

  filename        = "${path.module}/.terraform/tmp/tracker.dbxml"
  content         = local.tracker_dbxml_rendered
  file_permission = "0644"
}

resource "azurerm_storage_share_file" "tracker_dbxml" {
  count = var.enable_cassandra_tracker ? 1 : 0

  name = "tracker.dbxml"
  # Use .url (not .id) to work around azurerm bug where storage_share_file fails
  # to parse the ARM-style share ID. https://github.com/hashicorp/terraform-provider-azurerm/issues/28032
  storage_share_id = azurerm_storage_share.conf_db_pool[0].url
  source           = local_file.tracker_dbxml[0].filename
  content_md5      = md5(local.tracker_dbxml_rendered)
}
