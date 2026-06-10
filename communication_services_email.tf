# Auto-registers Microsoft.Communication on the subscription. Destroying this
# stack will unregister the namespace — share-the-subscription deployments
# should keep the feature enabled or pre-register via `az provider register`.
resource "azurerm_resource_provider_registration" "communication" {
  count = var.enable_communication_services_email ? 1 : 0

  name = "Microsoft.Communication"
}

resource "azurerm_email_communication_service" "this" {
  count = var.enable_communication_services_email ? 1 : 0

  name                = "${substr(local.name_prefix_slug, 0, 46)}-acse"
  resource_group_name = azurerm_resource_group.rg.name
  data_location       = local.acs_data_location

  depends_on = [azurerm_resource_provider_registration.communication]

  tags = merge(
    var.tags, {
      "Service" = "CommunicationServicesEmail"
    }
  )
}

# AzureManaged domains must use the literal name "AzureManagedDomain"; the
# platform rejects any other value when domain_management = "AzureManaged".
resource "azurerm_email_communication_service_domain" "this" {
  count = var.enable_communication_services_email ? 1 : 0

  name              = "AzureManagedDomain"
  email_service_id  = azurerm_email_communication_service.this[0].id
  domain_management = "AzureManaged"

  tags = merge(
    var.tags, {
      "Service" = "CommunicationServicesEmail"
    }
  )
}

resource "azurerm_email_communication_service_domain_sender_username" "this" {
  count = var.enable_communication_services_email ? 1 : 0

  name                    = var.communication_email_sender_username
  email_service_domain_id = azurerm_email_communication_service_domain.this[0].id
  display_name            = "Martini"
}

resource "azurerm_communication_service" "this" {
  count = var.enable_communication_services_email ? 1 : 0

  name                = "${substr(local.name_prefix_slug, 0, 47)}-acs"
  resource_group_name = azurerm_resource_group.rg.name
  data_location       = local.acs_data_location

  depends_on = [azurerm_resource_provider_registration.communication]

  tags = merge(
    var.tags, {
      "Service" = "CommunicationServices"
    }
  )
}

resource "azurerm_communication_service_email_domain_association" "this" {
  count = var.enable_communication_services_email ? 1 : 0

  communication_service_id = azurerm_communication_service.this[0].id
  email_service_domain_id  = azurerm_email_communication_service_domain.this[0].id
}

resource "azurerm_role_assignment" "acs_smtp_email_owner" {
  count = var.enable_communication_services_email ? 1 : 0

  scope                = azurerm_communication_service.this[0].id
  role_definition_name = "Communication and Email Service Owner"
  principal_id         = var.communication_email_smtp_entra_app.sp_object_id
}

# Maps the freeform SMTP login string to the Entra application. ACS rejects
# every SMTP AUTH attempt until this resource exists; the azurerm provider
# does not expose it, so we use azapi against the ARM API directly.
# ARM rejects PUT when properties.username == resource name, so the resource
# name carries a `-smtp` suffix while the login string stays plain.
resource "azapi_resource" "acs_smtp_username" {
  count = var.enable_communication_services_email ? 1 : 0

  type      = "Microsoft.Communication/communicationServices/smtpUsernames@2025-09-01"
  name      = "${var.communication_email_sender_username}-smtp"
  parent_id = azurerm_communication_service.this[0].id

  body = {
    properties = {
      entraApplicationId = var.communication_email_smtp_entra_app.client_id
      tenantId           = data.azurerm_client_config.current.tenant_id
      username           = var.communication_email_sender_username
    }
  }

  depends_on = [azurerm_role_assignment.acs_smtp_email_owner]
}

# SMTP Username takes ~60-90s to reach Ready on the ACS side after the API
# returns; bump if Martini's first send still 535s.
resource "time_sleep" "acs_smtp_role_propagation" {
  count = var.enable_communication_services_email ? 1 : 0

  depends_on = [
    azurerm_role_assignment.acs_smtp_email_owner,
    azurerm_communication_service_email_domain_association.this,
    azapi_resource.acs_smtp_username,
  ]
  create_duration = "120s"
}

locals {
  acs_smtp_username = var.enable_communication_services_email ? var.communication_email_sender_username : null

  acs_sender_address = var.enable_communication_services_email ? format(
    "%s@%s",
    azurerm_email_communication_service_domain_sender_username.this[0].name,
    azurerm_email_communication_service_domain.this[0].from_sender_domain,
  ) : null
}
