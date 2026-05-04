output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "resource_group_location" {
  value = azurerm_resource_group.rg.location
}

output "app_gw_url" {
  value = var.appgw_use_kv_cert ? "https://${var.custom_domain}" : "https://${azurerm_public_ip.app_gw_pip.fqdn}"
}

output "app_gw_public_ip" {
  description = "Public IP of the Application Gateway. Point your custom-domain A record at this address."
  value       = azurerm_public_ip.app_gw_pip.ip_address
}

output "next_steps" {
  description = "Follow-up actions when a custom domain is configured but the listener has not yet been switched to the Key Vault cert."
  value = (var.custom_domain != null && !var.appgw_use_kv_cert) ? join("\n", [
    "",
    "Custom-domain TLS is configured in two phases. Current phase: 1 of 2.",
    "",
    "1. Add a DNS A record at your DNS provider:",
    "     ${var.custom_domain}  →  ${azurerm_public_ip.app_gw_pip.ip_address}",
    "",
    "2. Confirm the cert was issued:",
    "     az keyvault certificate show --vault-name ${azurerm_key_vault.key_vault.name} --name ${replace(var.custom_domain, ".", "-")}",
    "",
    "3. Switch the App Gateway listener to the Key Vault cert:",
    "     terraform apply -var=appgw_use_kv_cert=true",
    "",
  ]) : null
}

output "subnet_prefixes" {
  value = {
    for name, subnet in module.virtual_network.subnets :
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

output "service_bus_endpoint" {
  value = var.enable_service_bus ? azurerm_servicebus_namespace.this[0].endpoint : null
}

output "service_bus_namespace_name" {
  value = var.enable_service_bus ? azurerm_servicebus_namespace.this[0].name : null
}

output "service_bus_queue_names" {
  value = var.enable_service_bus ? [for q in azurerm_servicebus_queue.queues : q.name] : []
}

output "service_bus_topic_names" {
  value = var.enable_service_bus ? [for t in azurerm_servicebus_topic.topics : t.name] : []
}