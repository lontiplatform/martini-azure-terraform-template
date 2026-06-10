resource "azurerm_eventhub_namespace" "this" {
  count = var.enable_event_hub ? 1 : 0

  name                = "${substr(local.name_prefix_slug, 0, 47)}-eh"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = var.event_hub_namespace_sku
  capacity            = var.event_hub_namespace_sku == "Basic" ? null : var.event_hub_capacity

  # CES preview only supports Event Hubs public endpoints; private endpoints
  # and service-endpoint-only namespaces are rejected.
  public_network_access_enabled = true
  minimum_tls_version           = "1.2"
  local_authentication_enabled  = true

  tags = merge(
    var.tags, {
      "Service" = "EventHub"
    }
  )
}

resource "azurerm_eventhub_namespace_authorization_rule" "martini_listener" {
  count = var.enable_event_hub ? 1 : 0

  name                = "martini-listener"
  namespace_name      = azurerm_eventhub_namespace.this[0].name
  resource_group_name = azurerm_resource_group.rg.name

  listen = true
  send   = false
  manage = false
}

resource "azurerm_eventhub" "this" {
  for_each = var.enable_event_hub ? var.event_hubs : {}

  name              = each.key
  namespace_id      = azurerm_eventhub_namespace.this[0].id
  partition_count   = each.value.partition_count
  message_retention = each.value.message_retention
}

data "azurerm_mssql_server" "ces_source" {
  count = var.enable_event_hub && var.ces_source_sql_server != null ? 1 : 0

  name                = var.ces_source_sql_server.name
  resource_group_name = var.ces_source_sql_server.resource_group_name
}

locals {
  ces_source_principal_id = (
    !var.enable_event_hub ? null :
    var.ces_source_sql_server != null ? data.azurerm_mssql_server.ces_source[0].identity[0].principal_id :
    var.enable_sql_server ? try(module.sql_server[0].resource.identity[0].principal_id, null) :
    null
  )
}

resource "azurerm_role_assignment" "ces_azure_sql_to_eh" {
  for_each = (
    var.enable_event_hub && (var.ces_source_sql_server != null || var.enable_sql_server)
    ? azurerm_eventhub.this
    : {}
  )

  scope                = each.value.id
  role_definition_name = "Azure Event Hubs Data Sender"
  principal_id         = local.ces_source_principal_id
}

# Azure RBAC propagates with eventual consistency; the assignment may not be
# visible to Event Hubs for 1-2 minutes. Holding `terraform apply` here means
# the post-apply T-SQL CES bootstrap can authenticate immediately.
resource "time_sleep" "ces_role_propagation" {
  count = var.enable_event_hub && (var.ces_source_sql_server != null || var.enable_sql_server) ? 1 : 0

  depends_on      = [azurerm_role_assignment.ces_azure_sql_to_eh]
  create_duration = "300s"
}

locals {
  martini_eh_consumer_group = "$Default"
}

resource "azurerm_role_assignment" "martini_designer_eh_receiver" {
  for_each = var.enable_event_hub && var.enable_designer ? azurerm_eventhub.this : {}

  scope                = each.value.id
  role_definition_name = "Azure Event Hubs Data Receiver"
  principal_id         = azurerm_container_app.martini_designer[0].identity[0].principal_id
}

resource "azurerm_role_assignment" "martini_runtime_eh_receiver" {
  for_each = var.enable_event_hub && !var.enable_designer && length(var.event_hubs) > 0 ? azurerm_eventhub.this : {}

  scope                = each.value.id
  role_definition_name = "Azure Event Hubs Data Receiver"
  principal_id         = azurerm_container_app.martini[0].identity[0].principal_id
}

# Hold apply long enough for RBAC to propagate so Martini's first connect succeeds.
resource "time_sleep" "martini_eh_role_propagation" {
  count = var.enable_event_hub && length(var.event_hubs) > 0 ? 1 : 0

  depends_on = [
    azurerm_role_assignment.martini_designer_eh_receiver,
    azurerm_role_assignment.martini_runtime_eh_receiver,
  ]
  create_duration = "300s"
}
