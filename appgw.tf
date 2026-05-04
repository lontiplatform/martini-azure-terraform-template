// Self-signed certificate path. Used whenever the AppGW listener is not
// pointed at a Key-Vault-stored cert (`appgw_use_kv_cert = false`), which is
// also the default when no custom domain is configured.
resource "tls_private_key" "app_gw" {
  count = var.appgw_use_kv_cert ? 0 : 1

  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_self_signed_cert" "app_gw" {
  count = var.appgw_use_kv_cert ? 0 : 1

  private_key_pem = tls_private_key.app_gw[0].private_key_pem

  subject {
    common_name = azurerm_public_ip.app_gw_pip.fqdn
  }

  dns_names = [azurerm_public_ip.app_gw_pip.fqdn]

  validity_period_hours = 8760
  early_renewal_hours   = 720

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

resource "random_password" "app_gw_pfx" {
  count = var.appgw_use_kv_cert ? 0 : 1

  length  = 24
  special = false
}

resource "pkcs12_from_pem" "app_gw" {
  count = var.appgw_use_kv_cert ? 0 : 1

  password        = random_password.app_gw_pfx[0].result
  cert_pem        = tls_self_signed_cert.app_gw[0].cert_pem
  private_key_pem = tls_private_key.app_gw[0].private_key_pem
}

module "app_gw" {
  source  = "Azure/avm-res-network-applicationgateway/azurerm"
  version = "~> 0.4.2"

  name                = "${local.name_prefix}-app-gw"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  backend_address_pools = {
    appGatewayBackendPool = {
      name         = "appGatewayBackendPool"
      ip_addresses = var.enable_designer ? azurerm_container_group.martini_designer[*].ip_address : azurerm_container_group.martini[*].ip_address
    }
  }
  backend_http_settings = {
    appGatewayBackendHttpSettings = {
      name                  = "appGatewayBackendHttpSettings"
      port                  = var.enable_designer ? local.designer_ui_port : local.aci_container_port
      protocol              = "Http"
      cookie_based_affinity = "Enabled"
      probe_name            = "appGatewayBackendProbe"
    }
  }
  probe_configurations = {
    appGatewayBackendProbe = {
      name                = "appGatewayBackendProbe"
      protocol            = "Http"
      path                = var.enable_designer ? "/" : "/statistics/status"
      host                = "127.0.0.1"
      interval            = 15
      timeout             = 10
      unhealthy_threshold = 6
      match = {
        status_code = ["200-399"]
      }
    }
  }
  frontend_ports = {
    frontend-port-443 = {
      name = "frontend-port-443"
      port = 443
    }
  }
  ssl_certificates = var.appgw_use_kv_cert ? {
    appGatewaySslCert = {
      name                = "appGatewaySslCert"
      key_vault_secret_id = data.azurerm_key_vault_certificate.appgw[0].versionless_secret_id
    }
    } : {
    appGatewaySslCert = {
      name     = "appGatewaySslCert"
      data     = pkcs12_from_pem.app_gw[0].result
      password = random_password.app_gw_pfx[0].result
    }
  }
  ssl_policy = {
    policy_type = "Predefined"
    policy_name = "AppGwSslPolicy20220101"
  }
  gateway_ip_configuration = {
    subnet_id = module.virtual_network.subnets["public_subnet1"].resource.id
  }
  managed_identities = var.appgw_use_kv_cert ? {
    user_assigned_resource_ids = [azurerm_user_assigned_identity.appgw_kv[0].id]
  } : {}
  http_listeners = {
    appGatewayHttpsListener = {
      name                 = "appGatewayHttpsListener"
      frontend_port_name   = "frontend-port-443"
      host_name            = var.appgw_use_kv_cert ? var.custom_domain : azurerm_public_ip.app_gw_pip.fqdn
      ssl_certificate_name = "appGatewaySslCert"
    }
  }
  request_routing_rules = {
    routing-rule-1 = {
      name                       = "rule-1"
      rule_type                  = "Basic"
      http_listener_name         = "appGatewayHttpsListener"
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

resource "random_string" "pip_dns_suffix" {
  length  = 6
  upper   = false
  special = false
  numeric = true
}

resource "azurerm_public_ip" "app_gw_pip" {
  name                = "${local.name_prefix}-public-ip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  domain_name_label   = "${local.name_prefix}-${random_string.pip_dns_suffix.result}"
  zones               = ["1", "2", "3"]

  tags = merge(
    var.tags, {
      "Service" = "ApplicationGateway"
    }
  )
}