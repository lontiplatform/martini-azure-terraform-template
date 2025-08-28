// Name of the resource group created for the application
output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

// The Azure region where the Martini resources are deployed.
output "resource_group_location" {
  value = azurerm_resource_group.rg.location
}

// Application Gateway's URL
output "app_gw_url" {
  value = "http://${azurerm_public_ip.app_gw_pip.fqdn}"
}

// CIDRs
output "subnet_prefixes" {
  value = {
    for name, subnet in module.virtual_network.subnets :
    name => subnet.resource.body.properties.addressPrefixes[0]
  }
}