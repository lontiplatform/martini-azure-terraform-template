locals {
  acmebot_enabled = var.custom_domain != ""

  # KV cert names must match ^[a-zA-Z0-9-]+$, so dots become dashes.
  custom_cert_name = local.acmebot_enabled ? replace(var.custom_domain, ".", "-") : ""

  # polymind-inc/acmebot: app_base_name must be [a-z0-9-], end alphanumeric,
  # and keep func-${app_base_name} within 32 chars (so <= 27).
  acmebot_app_base_name = substr("${replace(local.name_prefix_slug, "-", "")}acme", 0, 24)

  acmebot_function_host = local.acmebot_enabled ? "func-${local.acmebot_app_base_name}.azurewebsites.net" : ""
}

# AppGW cannot use a system-assigned MI for Key Vault cert references — a
# user-assigned MI is required.
resource "azurerm_user_assigned_identity" "appgw_kv" {
  count = local.acmebot_enabled ? 1 : 0

  name                = "${local.name_prefix}-appgw-kv-mi"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  tags = var.tags
}

resource "azurerm_role_assignment" "acmebot_user_key_op" {
  count = local.acmebot_enabled ? 1 : 0

  scope                = azurerm_resource_group.rg.id
  role_definition_name = "Storage Account Key Operator Service Role"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "time_sleep" "acmebot_user_key_op_propagation" {
  count = local.acmebot_enabled ? 1 : 0

  depends_on      = [azurerm_role_assignment.acmebot_user_key_op]
  create_duration = "180s"
}

module "acmebot" {
  count = local.acmebot_enabled ? 1 : 0

  source  = "shibayan/keyvault-acmebot/azurerm"
  version = "~> 3.1"

  app_base_name       = local.acmebot_app_base_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  vault_uri     = azurerm_key_vault.key_vault.vault_uri
  mail_address  = var.acme_contact_email
  acme_endpoint = var.acme_endpoint

  route_53 = var.acmebot_route53

  additional_tags = var.tags

  depends_on = [time_sleep.acmebot_user_key_op_propagation]
}

# `depends_on` defers the cert data source read below to apply-time, so a
# single apply can both issue the cert and wire it into the AppGW listener.
resource "null_resource" "issue_cert" {
  count = local.acmebot_enabled ? 1 : 0

  triggers = {
    domain        = var.custom_domain
    acme_endpoint = var.acme_endpoint
    vault_uri     = azurerm_key_vault.key_vault.vault_uri
  }

  provisioner "local-exec" {
    command = "${path.module}/scripts/issue-cert.sh"

    environment = {
      DOMAIN        = var.custom_domain
      CERT_NAME     = local.custom_cert_name
      FUNCTION_HOST = local.acmebot_function_host
      FUNCTION_KEY  = module.acmebot[0].api_key
      KV_NAME       = azurerm_key_vault.key_vault.name
      ACME_ENDPOINT = var.acme_endpoint
    }
  }

  depends_on = [
    module.acmebot,
    azurerm_key_vault_access_policy.acmebot,
  ]
}

data "azurerm_key_vault_certificate" "appgw_custom" {
  count = local.acmebot_enabled ? 1 : 0

  name         = local.custom_cert_name
  key_vault_id = azurerm_key_vault.key_vault.id

  depends_on = [null_resource.issue_cert]
}

data "azurerm_key_vault_secret" "appgw_custom_pfx" {
  count = local.acmebot_enabled ? 1 : 0

  name         = local.custom_cert_name
  key_vault_id = azurerm_key_vault.key_vault.id

  depends_on = [null_resource.issue_cert]
}
