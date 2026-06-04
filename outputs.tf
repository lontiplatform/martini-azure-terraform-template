output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "resource_group_location" {
  value = azurerm_resource_group.rg.location
}

output "app_gw_url" {
  value = "https://${azurerm_public_ip.app_gw_pip.fqdn}"
}

output "app_gw_public_ip" {
  value = azurerm_public_ip.app_gw_pip.ip_address
}

output "subnet_prefixes" {
  value = local.byo_vnet ? {
    aci       = var.aci_subnet_cidr
    appgw     = var.appgw_subnet_cidr
    cassandra = var.enable_cassandra_tracker ? var.cassandra_subnet_cidr : null
    } : {
    for name, subnet in module.virtual_network[0].subnets :
    name => subnet.resource.body.properties.addressPrefixes[0]
  }
}

output "cassandra_contact_point" {
  value = var.enable_cassandra_tracker ? local.cassandra_node_fqdns[0] : null
}

output "cassandra_port" {
  value = var.enable_cassandra_tracker ? 9042 : null
}

output "cassandra_cluster_name" {
  value = var.enable_cassandra_tracker ? azurerm_cosmosdb_cassandra_cluster.tracker[0].name : null
}

output "event_hub_namespace_name" {
  value = var.enable_event_hub ? azurerm_eventhub_namespace.this[0].name : null
}

output "event_hub_namespace_fqdn" {
  value = var.enable_event_hub ? "${azurerm_eventhub_namespace.this[0].name}.servicebus.windows.net" : null
}

output "event_hub_names" {
  value = var.enable_event_hub ? sort([for h in azurerm_eventhub.this : h.name]) : []
}

output "log_analytics_workspace_name" {
  value = var.enable_log_analytics ? azurerm_log_analytics_workspace.this[0].name : null
}

output "log_analytics_workspace_id" {
  value = var.enable_log_analytics ? azurerm_log_analytics_workspace.this[0].id : null
}

output "communication_services_smtp_host" {
  value = var.enable_communication_services_email ? "smtp.azurecomm.net" : null
}

output "communication_services_smtp_port" {
  value = var.enable_communication_services_email ? 587 : null
}

output "communication_services_sender_address" {
  value = local.acs_sender_address
}

output "communication_services_email_domain" {
  value = var.enable_communication_services_email ? azurerm_email_communication_service_domain.this[0].from_sender_domain : null
}

output "custom_domain_url" {
  value       = local.acmebot_enabled ? "https://${var.custom_domain}" : null
  description = "Public HTTPS URL of the custom-domain listener once the A record for var.custom_domain is pointed at app_gw_public_ip."
}

output "acmebot_function_host" {
  value       = local.acmebot_enabled ? local.acmebot_function_host : null
  description = "Default hostname of the keyvault-acmebot Function App. Useful for operator debugging (e.g. log tail, manual /api/certificate POSTs)."
}

output "acmebot_function_key" {
  value       = local.acmebot_enabled ? module.acmebot[0].api_key : null
  description = "Default Functions API key for the keyvault-acmebot Function App. Required for any manual call to /api/certificate."
  sensitive   = true
}