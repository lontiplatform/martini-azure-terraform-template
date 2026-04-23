resource "azurerm_servicebus_namespace" "this" {
  count = var.enable_service_bus ? 1 : 0

  name                = "${local.name_prefix}-sb"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = var.service_bus_sku

  # Premium-only arguments; null on Basic/Standard so the provider ignores them.
  capacity                     = var.service_bus_sku == "Premium" ? var.service_bus_capacity : null
  premium_messaging_partitions = var.service_bus_sku == "Premium" ? var.service_bus_premium_messaging_partitions : null

  minimum_tls_version           = "1.2"
  public_network_access_enabled = true
  local_auth_enabled            = true

  tags = merge(
    var.tags, {
      "Service" = "ServiceBus"
    }
  )
}

# Send-only rule issued to the external publisher (e.g. Azure SQL CES).
resource "azurerm_servicebus_namespace_authorization_rule" "ces_send" {
  count = var.enable_service_bus ? 1 : 0

  name         = "ces-send"
  namespace_id = azurerm_servicebus_namespace.this[0].id

  listen = false
  send   = true
  manage = false
}

# Listen-only rule used by Martini to consume messages.
resource "azurerm_servicebus_namespace_authorization_rule" "martini_listen" {
  count = var.enable_service_bus ? 1 : 0

  name         = "martini-listen"
  namespace_id = azurerm_servicebus_namespace.this[0].id

  listen = true
  send   = false
  manage = false
}

resource "azurerm_servicebus_queue" "queues" {
  for_each = var.enable_service_bus ? toset(var.service_bus_queues) : toset([])

  name         = each.value
  namespace_id = azurerm_servicebus_namespace.this[0].id
}

resource "azurerm_servicebus_topic" "topics" {
  for_each = var.enable_service_bus ? toset(var.service_bus_topics) : toset([])

  name         = each.value
  namespace_id = azurerm_servicebus_namespace.this[0].id
}

resource "azurerm_servicebus_subscription" "martini_subs" {
  for_each = var.enable_service_bus ? toset(var.service_bus_topics) : toset([])

  name               = "martini"
  topic_id           = azurerm_servicebus_topic.topics[each.value].id
  max_delivery_count = 10
}
