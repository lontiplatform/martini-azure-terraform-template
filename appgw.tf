module "app_gw" {
  #checkov:skip=CKV_TF_1:Module version is used instead of hash
  #checkov:skip=CKV_AZURE_218:HTTPS is currently not required for this template
  source  = "Azure/avm-res-network-applicationgateway/azurerm"
  version = "~> 0.4.2"

  name                = "${local.name_prefix}-app-gw"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  backend_address_pools = {
    appGatewayBackendPool = {
      name         = "appGatewayBackendPool"
      ip_addresses = [azurerm_container_group.martini.ip_address]
    }
  }
  backend_http_settings = {
    appGatewayBackendHttpSettings = {
      name                  = "appGatewayBackendHttpSettings"
      port                  = local.aci_container_port
      protocol              = "Http"
      cookie_based_affinity = "Disabled"
    }
  }
  frontend_ports = {
    frontend-port-80 = {
      name = "frontend-port-80"
      port = 80
    }
  }
  gateway_ip_configuration = {
    subnet_id = local.public_subnet1_id
  }
  http_listeners = {
    appGatewayHttpListener = {
      name               = "appGatewayHttpListener"
      frontend_port_name = "frontend-port-80"
    }
  }
  request_routing_rules = {
    routing-rule-1 = {
      name                       = "rule-1"
      rule_type                  = "Basic"
      http_listener_name         = "appGatewayHttpListener"
      backend_address_pool_name  = "appGatewayBackendPool"
      backend_http_settings_name = "appGatewayBackendHttpSettings"
      priority                   = 100
    }
  }

  create_public_ip      = false
  public_ip_resource_id = azurerm_public_ip.app_gw_pip.id

  tags = merge(
    var.tags, {
      "Service" = "ApplicationGateway"
    }
  )
}

resource "azurerm_public_ip" "app_gw_pip" {
  name                = "${local.name_prefix}-public-ip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  domain_name_label   = local.name_prefix
  zones               = ["1", "2", "3"]

  tags = merge(
    var.tags, {
      "Service" = "ApplicationGateway"
    }
  )
}