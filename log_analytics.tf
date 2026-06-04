resource "azurerm_log_analytics_workspace" "this" {
  count = var.enable_log_analytics ? 1 : 0

  name                = "${local.name_prefix}-law"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = var.tags
}

resource "azurerm_monitor_diagnostic_setting" "conf_file" {
  count = var.enable_log_analytics ? 1 : 0

  name                       = "${local.name_prefix}-conf-file-diag"
  target_resource_id         = "${azurerm_storage_account.conf.id}/fileServices/default"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this[0].id

  enabled_log { category = "StorageRead" }
  enabled_log { category = "StorageWrite" }
  enabled_log { category = "StorageDelete" }

  enabled_metric {
    category = "Transaction"
  }
}
