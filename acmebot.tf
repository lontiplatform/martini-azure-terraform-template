// acmebot deployment + certificate issuance + identity wiring for the
// Application Gateway. Everything in this file is gated on `var.custom_domain`.

locals {
  acmebot_enabled = var.custom_domain != null

  // app_base_name must be alphanumeric and keep the generated function-app
  // name (`func-${app_base_name}`) ≤ 32 chars. Strip dashes from name_prefix
  // and truncate.
  acmebot_app_base_name = local.acmebot_enabled ? substr(replace(lower(local.name_prefix), "/[^a-z0-9]/", ""), 0, 25) : ""

  // Key Vault cert object name. Azure restricts cert names to alphanumerics +
  // dashes, so map dots to dashes.
  cert_name = local.acmebot_enabled ? replace(var.custom_domain, ".", "-") : ""
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

  allowed_ip_addresses = var.acmebot_allowed_ips

  cloudflare    = try(var.acmebot_dns_provider.cloudflare, null)
  route_53      = try(var.acmebot_dns_provider.route_53, null)
  azure_dns     = try(var.acmebot_dns_provider.azure_dns, null)
  google_dns    = try(var.acmebot_dns_provider.google_dns, null)
  go_daddy      = try(var.acmebot_dns_provider.go_daddy, null)
  gandi         = try(var.acmebot_dns_provider.gandi, null)
  dns_made_easy = try(var.acmebot_dns_provider.dns_made_easy, null)

  additional_tags = merge(var.tags, {
    "Service" = "Acmebot"
  })
}

// User-assigned identity the Application Gateway will use to read the
// certificate from Key Vault once `appgw_use_kv_cert = true`.
resource "azurerm_user_assigned_identity" "appgw_kv" {
  count = local.acmebot_enabled ? 1 : 0

  name                = "${local.name_prefix}-appgw-kv"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  tags = merge(var.tags, {
    "Service" = "ApplicationGateway"
  })
}

// Grant acmebot's system-assigned MI permission to manage certificates and
// read their secret representation in the existing Key Vault.
resource "azurerm_key_vault_access_policy" "acmebot" {
  count = local.acmebot_enabled ? 1 : 0

  key_vault_id = azurerm_key_vault.key_vault.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = module.acmebot[0].principal_id

  certificate_permissions = [
    "Get", "List", "Create", "Update", "Import", "Delete", "Recover",
  ]
  secret_permissions = [
    "Get", "List",
  ]
}

// Grant the AppGW user-assigned identity read access to certs/secrets so the
// listener can pull the cert via key_vault_secret_id.
resource "azurerm_key_vault_access_policy" "appgw_kv" {
  count = local.acmebot_enabled ? 1 : 0

  key_vault_id = azurerm_key_vault.key_vault.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_user_assigned_identity.appgw_kv[0].principal_id

  certificate_permissions = ["Get"]
  secret_permissions      = ["Get"]
}

// Trigger acmebot to issue the certificate as part of `terraform apply`. The
// helper script is idempotent: if the cert already exists with > 30 days of
// remaining validity, it exits 0 without calling acmebot.
resource "null_resource" "issue_cert" {
  count = local.acmebot_enabled ? 1 : 0

  triggers = {
    domain        = var.custom_domain
    cert_name     = local.cert_name
    acme_endpoint = var.acme_endpoint
    function_name = module.acmebot[0].principal_id
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      DOMAIN        = var.custom_domain
      CERT_NAME     = local.cert_name
      FUNCTION_HOST = "func-${local.acmebot_app_base_name}.azurewebsites.net"
      FUNCTION_KEY  = module.acmebot[0].api_key
      KV_NAME       = azurerm_key_vault.key_vault.name
    }
    command = file("${path.module}/scripts/issue-cert.sh")
  }

  depends_on = [
    azurerm_key_vault_access_policy.acmebot,
  ]
}

// Read the issued certificate so the AppGW listener can reference it.
// Only resolved on the second apply, after the cert exists.
data "azurerm_key_vault_certificate" "appgw" {
  count = var.appgw_use_kv_cert ? 1 : 0

  name         = local.cert_name
  key_vault_id = azurerm_key_vault.key_vault.id

  depends_on = [
    null_resource.issue_cert,
  ]
}
