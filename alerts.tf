locals {
  alert_aca_scopes = var.enable_designer ? [for app in azurerm_container_app.martini_designer : app.id] : [for app in azurerm_container_app.martini : app.id]

  alert_aca_memory_threshold_bytes = var.martini_memory * 0.9 * 1024 * 1024 * 1024
}

resource "azurerm_monitor_action_group" "ops" {
  name                = "${local.name_prefix}-ops"
  resource_group_name = azurerm_resource_group.rg.name
  short_name          = "martiniops"

  dynamic "email_receiver" {
    for_each = var.alert_emails
    content {
      name                    = "email-${replace(email_receiver.value, "@", "-at-")}"
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }

  tags = var.tags
}

resource "azurerm_monitor_metric_alert" "storage_availability" {
  name                     = "${local.name_prefix}-storage-availability"
  resource_group_name      = azurerm_resource_group.rg.name
  scopes                   = ["${azurerm_storage_account.conf.id}/fileServices/default"]
  target_resource_type     = "Microsoft.Storage/storageAccounts/fileServices"
  target_resource_location = azurerm_storage_account.conf.location
  description              = "Azure Files availability for the conf storage account dropped below 99%."
  severity                 = 2
  frequency                = "PT5M"
  window_size              = "PT15M"

  criteria {
    metric_namespace = "Microsoft.Storage/storageAccounts/fileServices"
    metric_name      = "Availability"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 99
  }

  action {
    action_group_id = azurerm_monitor_action_group.ops.id
  }

  tags = var.tags
}

resource "azurerm_monitor_metric_alert" "storage_e2e_latency" {
  name                     = "${local.name_prefix}-storage-e2e-latency"
  resource_group_name      = azurerm_resource_group.rg.name
  scopes                   = ["${azurerm_storage_account.conf.id}/fileServices/default"]
  target_resource_type     = "Microsoft.Storage/storageAccounts/fileServices"
  target_resource_location = azurerm_storage_account.conf.location
  description              = "End-to-end latency on the conf Azure Files share exceeded 100ms average over 15 minutes."
  severity                 = 3
  frequency                = "PT5M"
  window_size              = "PT15M"

  criteria {
    metric_namespace = "Microsoft.Storage/storageAccounts/fileServices"
    metric_name      = "SuccessE2ELatency"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 100
  }

  action {
    action_group_id = azurerm_monitor_action_group.ops.id
  }

  tags = var.tags
}

resource "azurerm_monitor_metric_alert" "aca_memory_high" {
  count = length(local.alert_aca_scopes) > 0 ? 1 : 0

  name                = "${local.name_prefix}-aca-memory-high"
  resource_group_name = azurerm_resource_group.rg.name
  scopes              = local.alert_aca_scopes
  description         = "Martini container memory usage exceeded 90% of the provisioned allocation."
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"

  criteria {
    metric_namespace = "Microsoft.App/containerApps"
    metric_name      = "WorkingSetBytes"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = local.alert_aca_memory_threshold_bytes
  }

  action {
    action_group_id = azurerm_monitor_action_group.ops.id
  }

  tags = var.tags
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "storage_throttling" {
  count = var.enable_log_analytics ? 1 : 0

  name                 = "${local.name_prefix}-storage-throttling"
  resource_group_name  = azurerm_resource_group.rg.name
  location             = azurerm_resource_group.rg.location
  description          = "Azure Files throttling/server-busy/network errors detected on the conf account (excludes benign SMB status codes and OBJECT_NAME_NOT_FOUND noise)."
  severity             = 2
  evaluation_frequency = "PT5M"
  window_duration      = "PT5M"
  scopes               = [azurerm_log_analytics_workspace.this[0].id]

  criteria {
    query                   = <<-KQL
      StorageFileLogs
      | where AccountName == "${azurerm_storage_account.conf.name}"
      | where StatusText in (
          "ClientThrottlingError",
          "ServerBusyError",
          "NetworkError",
          "ClientTimeoutError",
          "ServerTimeoutError",
          "AuthenticationFailed",
          "AuthorizationFailure"
        )
    KQL
    operator                = "GreaterThan"
    threshold               = 10
    time_aggregation_method = "Count"
  }

  action {
    action_groups = [azurerm_monitor_action_group.ops.id]
  }

  tags = var.tags
}

resource "azurerm_monitor_activity_log_alert" "aca_terminations" {
  name                = "${local.name_prefix}-aca-terminations"
  location            = "global"
  resource_group_name = azurerm_resource_group.rg.name
  scopes              = [azurerm_resource_group.rg.id]
  description         = "Failed administrative operation against a Martini container app. Excludes successful (planned) deletes to keep Terraform-driven replacements silent."

  criteria {
    category       = "Administrative"
    resource_type  = "Microsoft.App/containerApps"
    operation_name = "Microsoft.App/containerApps/delete"
    level          = "Error"
    status         = "Failed"
  }

  action {
    action_group_id = azurerm_monitor_action_group.ops.id
  }

  tags = var.tags
}
