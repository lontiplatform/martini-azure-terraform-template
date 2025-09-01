resource "azurerm_resource_group" "rg" {
  name     = "${local.name_prefix}-resource-group"
  location = var.rg_location
  tags     = var.tags
}