output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "resource_group_location" {
  value = azurerm_resource_group.rg.location
}

output "app_gw_url" {
  value = "http://${azurerm_public_ip.app_gw_pip.fqdn}"
}

output "subnet_prefixes" {
  value = {
    for name, subnet in module.virtual_network.subnets :
    name => subnet.resource.body.properties.addressPrefixes[0]
  }
}

output "cassandra_contact_point" {
  value = var.enable_cassandra_tracker ? azurerm_cosmosdb_cassandra_datacenter.tracker[0].seed_node_ip_addresses[0] : null
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
