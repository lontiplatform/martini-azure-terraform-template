module "app_gw" {
  source  = "Azure/avm-res-network-applicationgateway/azurerm"
  version = "~> 0.4.2"

  name                = "${local.name_prefix}-app-gw"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  backend_address_pools = {
    appGatewayBackendPool = {
      name         = "appGatewayBackendPool"
      ip_addresses = [azurerm_container_app_environment.this.static_ip_address]
    }
  }
  backend_http_settings = {
    appGatewayBackendHttpSettings = {
      name                                = "appGatewayBackendHttpSettings"
      port                                = 443
      protocol                            = "Https"
      cookie_based_affinity               = "Enabled"
      probe_name                          = "appGatewayBackendProbe"
      host_name                           = var.custom_domain
      pick_host_name_from_backend_address = false
    }
  }
  probe_configurations = {
    appGatewayBackendProbe = {
      name                                      = "appGatewayBackendProbe"
      protocol                                  = "Https"
      path                                      = var.enable_designer ? "/" : "/statistics/status"
      pick_host_name_from_backend_http_settings = true
      interval                                  = 30
      timeout                                   = 10
      unhealthy_threshold                       = 3
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
    frontend-port-80 = {
      name = "frontend-port-80"
      port = 80
    }
  }
  managed_identities = local.acmebot_enabled ? {
    user_assigned_resource_ids = [azurerm_user_assigned_identity.appgw_kv[0].id]
  } : {}

  ssl_certificates = local.acmebot_enabled ? {
    appGatewaySslCertCustom = {
      name                = "appGatewaySslCertCustom"
      key_vault_secret_id = data.azurerm_key_vault_certificate.appgw_custom[0].versionless_secret_id
    }
  } : {}
  ssl_policy = {
    policy_type          = "CustomV2"
    min_protocol_version = "TLSv1_2"
    cipher_suites = [
      "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256",
      "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384",
      "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256",
      "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384",
    ]
  }
  gateway_ip_configuration = {
    subnet_id = local.appgw_subnet_id
  }
  http_listeners = local.acmebot_enabled ? {
    appGatewayHttpListenerCustom = {
      name               = "appGatewayHttpListenerCustom"
      frontend_port_name = "frontend-port-80"
      host_name          = var.custom_domain
    }
    appGatewayHttpsListenerCustom = {
      name                 = "appGatewayHttpsListenerCustom"
      frontend_port_name   = "frontend-port-443"
      host_name            = var.custom_domain
      ssl_certificate_name = "appGatewaySslCertCustom"
      require_sni          = true
    }
    } : {
    appGatewayHttpListener = {
      name               = "appGatewayHttpListener"
      frontend_port_name = "frontend-port-80"
      host_name          = azurerm_public_ip.app_gw_pip.fqdn
    }
  }
  request_routing_rules = local.acmebot_enabled ? {
    routing-rule-http-custom = {
      name                        = "rule-http-custom"
      rule_type                   = "Basic"
      http_listener_name          = "appGatewayHttpListenerCustom"
      backend_address_pool_name   = ""
      backend_http_settings_name  = ""
      redirect_configuration_name = "to-https-custom"
      priority                    = 80
    }
    routing-rule-custom = {
      name                       = "rule-custom"
      rule_type                  = "Basic"
      http_listener_name         = "appGatewayHttpsListenerCustom"
      backend_address_pool_name  = "appGatewayBackendPool"
      backend_http_settings_name = "appGatewayBackendHttpSettings"
      priority                   = 90
    }
    } : {
    routing-rule-http = {
      name                       = "rule-http"
      rule_type                  = "Basic"
      http_listener_name         = "appGatewayHttpListener"
      backend_address_pool_name  = "appGatewayBackendPool"
      backend_http_settings_name = "appGatewayBackendHttpSettings"
      priority                   = 110
    }
  }

  redirect_configuration = local.acmebot_enabled ? {
    to-https-custom = {
      name                 = "to-https-custom"
      redirect_type        = "Permanent"
      target_listener_name = "appGatewayHttpsListenerCustom"
      include_path         = true
      include_query_string = true
    }
  } : null

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
  domain_name_label   = "${substr(local.name_prefix_slug, 0, 56)}-${random_string.pip_dns_suffix.result}"
  zones               = ["1", "2", "3"]

  tags = merge(
    var.tags, {
      "Service" = "ApplicationGateway"
    }
  )
}

resource "azurerm_monitor_diagnostic_setting" "app_gw" {
  count = var.enable_log_analytics ? 1 : 0

  name                       = "${local.name_prefix}-app-gw-diag"
  target_resource_id         = module.app_gw.application_gateway_id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this[0].id

  enabled_log { category = "ApplicationGatewayAccessLog" }
  enabled_log { category = "ApplicationGatewayPerformanceLog" }
  enabled_log { category = "ApplicationGatewayFirewallLog" }

  enabled_metric {
    category = "AllMetrics"
  }
}
