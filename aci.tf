resource "azurerm_container_group" "martini" {
  #checkov:skip=CKV2_AZURE_28:Managed Service Identity currently does not support container groups deployed in virtual networks.
  name                = "${local.name_prefix}-aci"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  ip_address_type     = "Private"
  os_type             = "Linux"

  container {
    name   = local.aci_service_name
    image  = var.aci_docker_image_url
    cpu    = var.cpu
    memory = var.memory
    security {
      privilege_enabled = false
    }

    ports {
      port = local.aci_container_port
    }

    secure_environment_variables = {
      MR_LICENSE = azurerm_key_vault_secret.martini_workspace_license.value
    }
  }

  subnet_ids = [module.virtual_network.subnets["private_subnet1"].resource.id]

  tags = var.tags
}