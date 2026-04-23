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
  value = var.enable_cassandra_tracker ? "${azurerm_cosmosdb_account.cassandra[0].name}.cassandra.cosmos.azure.com" : null
}

output "cassandra_port" {
  value = var.enable_cassandra_tracker ? 10350 : null
}

output "cassandra_keyspace_name" {
  value = var.enable_cassandra_tracker ? azurerm_cosmosdb_cassandra_keyspace.tracker[0].name : null
}

output "cassandra_account_name" {
  value = var.enable_cassandra_tracker ? azurerm_cosmosdb_account.cassandra[0].name : null
}
