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
output "private_subnet1_prefix" {
  value = module.virtual_network.subnets["private_subnet1"].resource.body.properties.addressPrefixes[0]
}


output "private_subnet2_prefix" {
  value = module.virtual_network.subnets["private_subnet2"].resource.body.properties.addressPrefixes[0]
}


output "public_subnet1_prefix" {
  value = module.virtual_network.subnets["public_subnet1"].resource.body.properties.addressPrefixes[0]
}


output "public_subnet2_prefix" {
  value = module.virtual_network.subnets["public_subnet2"].resource.body.properties.addressPrefixes[0]
}

