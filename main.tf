terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.37.0"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "rg" {
  name     = "${local.name_prefix}-resource-group"
  location = var.rg_location
  tags     = var.tags
}

locals {
  public_subnet1_id  = module.virtual_network.subnets["public_subnet1"].resource.id
  public_subnet2_id  = module.virtual_network.subnets["public_subnet2"].resource.id
  private_subnet1_id = module.virtual_network.subnets["private_subnet1"].resource.id
  private_subnet2_id = module.virtual_network.subnets["private_subnet2"].resource.id

  nsg_rules = {
    "AllowInternetOut" = {
      name                       = "AllowInternetOut"
      access                     = "Allow"
      destination_address_prefix = "*"
      destination_port_range     = "*"
      direction                  = "Outbound"
      priority                   = 200
      protocol                   = "*"
      source_address_prefix      = "*"
      source_port_range          = "*"
    }
  }

  name_prefix = "${terraform.workspace}-martini${var.name_suffix}"
}