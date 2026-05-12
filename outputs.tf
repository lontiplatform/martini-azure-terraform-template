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