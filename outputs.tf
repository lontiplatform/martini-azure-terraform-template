output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "resource_group_location" {
  value = azurerm_resource_group.rg.location
}

output "app_gw_url" {
  value = "http://${azurerm_public_ip.app_gw_pip.fqdn}"
}