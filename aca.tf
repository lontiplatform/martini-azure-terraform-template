resource "azurerm_container_app_environment" "this" {
  name                = "${local.name_prefix}-aca-env"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  log_analytics_workspace_id = var.enable_log_analytics ? azurerm_log_analytics_workspace.this[0].id : null

  infrastructure_subnet_id       = local.aca_subnet_id
  internal_load_balancer_enabled = false

  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }

  tags = var.tags
}

locals {
  aca_env_storages = merge(
    var.enable_designer ? {} : {
      "db-pool"        = { share_name = azurerm_storage_share.db_pool.name }
      "lib-ext"        = { share_name = azurerm_storage_share.runtime_lib_ext[0].name }
      "conf-overrides" = { share_name = azurerm_storage_share.runtime_conf_overrides[0].name }
      "packages"       = { share_name = azurerm_storage_share.runtime_packages[0].name }
    },
    var.enable_designer ? {
      "workspace-data" = { share_name = azurerm_storage_share.designer_workspace_data[0].name }
      "workspace-user" = { share_name = azurerm_storage_share.designer_workspace_user[0].name }
    } : {}
  )

  aca_mount_options = "uid=1001,gid=1001,file_mode=0777,dir_mode=0777"

  martini_runtime_env_pairs = concat(
    var.enable_cassandra_tracker ? [
      { name = "MR_TRACKER_ENABLE_EMBEDDED_DATABASE", value = "false" },
      { name = "MR_TRACKER_DATABASE_NAME", value = "tracker" },
      { name = "MR_TRACKER_DATABASE_USER", value = "cassandra" },
      { name = "MR_TRACKER_DATABASE_PASSWORD", secret_name = "cassandra-admin-password" },
    ] : [],
    var.enable_event_hub && length(var.event_hubs) > 0 ? [
      { name = "MR_EVENT_HUB_NAMESPACE_FQDN", value = "${azurerm_eventhub_namespace.this[0].name}.servicebus.windows.net" },
      { name = "MR_EVENT_HUB_NAMES", value = join(",", keys(var.event_hubs)) },
      { name = "MR_EVENT_HUB_CONSUMER_GROUP", value = local.martini_eh_consumer_group },
    ] : [],
    var.enable_communication_services_email ? [
      { name = "MR_SMTP_HOST", value = "smtp.azurecomm.net" },
      { name = "MR_SMTP_PORT", value = "587" },
      { name = "MR_SMTP_SENDER", value = local.acs_sender_address },
    ] : [],
    [
      { name = "MR_LICENSE", secret_name = "mr-license" },
    ],
    var.enable_event_hub && length(var.event_hubs) > 0 ? [
      { name = "MR_EVENT_HUB_CONNECTION_STRING", secret_name = "eh-connection-string" },
    ] : [],
    var.enable_communication_services_email ? [
      { name = "MR_SMTP_USERNAME", secret_name = "smtp-username" },
      { name = "MR_SMTP_PASSWORD", secret_name = "smtp-password" },
    ] : [],
  )

  martini_designer_env_pairs = concat(
    [
      { name = "MARTINI_WORKSPACE", value = "true" },
      { name = "MR_SERVER_HTTP_PORT", value = tostring(local.aci_container_port) },
      { name = "MR_SERVER_DESIGNER_PORT", value = tostring(local.designer_ui_port) },
      { name = "MR_PACKAGE_PROPERTIES_PREFIX", value = "QA" },
      { name = "MR_CORS_ENABLED", value = "true" },
      { name = "MR_CORS_ALLOWED_ORIGINS", value = "https://martini.lonti.com" },
    ],
    var.enable_cassandra_tracker ? [
      { name = "MR_TRACKER_ENABLE_EMBEDDED_DATABASE", value = "false" },
      { name = "MR_TRACKER_DATABASE_NAME", value = "tracker" },
      { name = "MR_TRACKER_DATABASE_USER", value = "cassandra" },
      { name = "MR_TRACKER_DATABASE_PASSWORD", secret_name = "cassandra-admin-password" },
    ] : [],
    var.enable_event_hub && length(var.event_hubs) > 0 ? [
      { name = "MR_EVENT_HUB_NAMESPACE_FQDN", value = "${azurerm_eventhub_namespace.this[0].name}.servicebus.windows.net" },
      { name = "MR_EVENT_HUB_NAMES", value = join(",", keys(var.event_hubs)) },
      { name = "MR_EVENT_HUB_CONSUMER_GROUP", value = local.martini_eh_consumer_group },
    ] : [],
    var.enable_communication_services_email ? [
      { name = "MR_SMTP_HOST", value = "smtp.azurecomm.net" },
      { name = "MR_SMTP_PORT", value = "587" },
      { name = "MR_SMTP_SENDER", value = local.acs_sender_address },
    ] : [],
    [
      { name = "MR_LICENSE", secret_name = "mr-license" },
    ],
    var.enable_event_hub && length(var.event_hubs) > 0 ? [
      { name = "MR_EVENT_HUB_CONNECTION_STRING", secret_name = "eh-connection-string" },
    ] : [],
    var.enable_communication_services_email ? [
      { name = "MR_SMTP_USERNAME", secret_name = "smtp-username" },
      { name = "MR_SMTP_PASSWORD", secret_name = "smtp-password" },
    ] : [],
  )

  martini_secrets = merge(
    {
      "mr-license" = azurerm_key_vault_secret.martini_workspace_license.value
    },
    local.designer_registry_credential != null ? {
      "registry-password" = local.designer_registry_credential.password
    } : {},
    var.enable_cassandra_tracker ? {
      "cassandra-admin-password" = random_password.cassandra_admin[0].result
    } : {},
    var.enable_event_hub && length(var.event_hubs) > 0 ? {
      "eh-connection-string" = azurerm_eventhub_namespace_authorization_rule.martini_listener[0].primary_connection_string
    } : {},
    var.enable_communication_services_email ? {
      "smtp-username" = local.acs_smtp_username
      "smtp-password" = var.communication_email_smtp_entra_app.client_secret
    } : {},
  )
}

resource "azurerm_container_app_environment_storage" "this" {
  for_each = local.aca_env_storages

  name                         = each.key
  container_app_environment_id = azurerm_container_app_environment.this.id
  account_name                 = azurerm_storage_account.conf.name
  share_name                   = each.value.share_name
  access_key                   = azurerm_storage_account.conf.primary_access_key
  access_mode                  = "ReadWrite"
}

resource "azurerm_container_app_environment_managed_certificate" "custom" {
  count = local.bind_custom_domain ? 1 : 0

  name                         = replace(var.custom_domain, ".", "-")
  container_app_environment_id = azurerm_container_app_environment.this.id
  subject_name                 = var.custom_domain
  domain_control_validation    = "CNAME"

  tags = var.tags

  # Azure refuses to issue the managed certificate until the hostname is already
  # registered on a container app in the environment, so the custom-domain
  # registration (binding type Disabled) must be created first.
  depends_on = [
    azurerm_container_app_custom_domain.martini,
    azurerm_container_app_custom_domain.martini_designer,
  ]
}

resource "azurerm_container_app" "martini" {
  count = var.enable_designer ? 0 : 1

  name                         = "${local.name_prefix}-runtime"
  container_app_environment_id = azurerm_container_app_environment.this.id
  resource_group_name          = azurerm_resource_group.rg.name
  revision_mode                = "Single"
  workload_profile_name        = "Consumption"

  identity {
    type = "SystemAssigned"
  }

  dynamic "secret" {
    for_each = local.martini_secrets
    content {
      name  = secret.key
      value = secret.value
    }
  }

  dynamic "registry" {
    for_each = local.designer_registry_credential != null ? [local.designer_registry_credential] : []
    content {
      server               = registry.value.server
      username             = registry.value.username
      password_secret_name = "registry-password"
    }
  }

  ingress {
    external_enabled           = true
    target_port                = local.aci_container_port
    transport                  = "auto"
    allow_insecure_connections = false

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = var.martini_node_count
    max_replicas = var.martini_node_count

    container {
      name   = local.aci_service_name
      image  = "${local.aci_docker_image_url}:${var.martini_version}"
      cpu    = var.martini_cpu
      memory = "${var.martini_memory}Gi"

      dynamic "env" {
        for_each = local.martini_runtime_env_pairs
        content {
          name        = env.value.name
          value       = lookup(env.value, "value", null)
          secret_name = lookup(env.value, "secret_name", null)
        }
      }

      liveness_probe {
        path                    = "/statistics/status"
        port                    = local.aci_container_port
        transport               = "HTTP"
        initial_delay           = 60
        interval_seconds        = 30
        timeout                 = 10
        failure_count_threshold = 3
      }

      readiness_probe {
        path                    = "/statistics/status"
        port                    = local.aci_container_port
        transport               = "HTTP"
        interval_seconds        = 10
        timeout                 = 5
        failure_count_threshold = 3
        success_count_threshold = 1
      }

      volume_mounts {
        name = "db-pool"
        path = "${var.martini_home_path}/conf/db-pool"
      }
      volume_mounts {
        name = "lib-ext"
        path = "${var.martini_home_path}/lib/ext"
      }
      volume_mounts {
        name = "conf-overrides"
        path = "${var.martini_home_path}/conf/overrides"
      }
      volume_mounts {
        name = "packages"
        path = "${var.martini_home_path}/packages"
      }
    }

    volume {
      name          = "db-pool"
      storage_type  = "AzureFile"
      storage_name  = azurerm_container_app_environment_storage.this["db-pool"].name
      mount_options = local.aca_mount_options
    }
    volume {
      name          = "lib-ext"
      storage_type  = "AzureFile"
      storage_name  = azurerm_container_app_environment_storage.this["lib-ext"].name
      mount_options = local.aca_mount_options
    }
    volume {
      name          = "conf-overrides"
      storage_type  = "AzureFile"
      storage_name  = azurerm_container_app_environment_storage.this["conf-overrides"].name
      mount_options = local.aca_mount_options
    }
    volume {
      name          = "packages"
      storage_type  = "AzureFile"
      storage_name  = azurerm_container_app_environment_storage.this["packages"].name
      mount_options = local.aca_mount_options
    }
  }

  tags = var.tags

  depends_on = [time_sleep.acs_smtp_role_propagation]
}

resource "azurerm_container_app" "martini_designer" {
  count = var.enable_designer ? 1 : 0

  name                         = "${local.name_prefix}-designer"
  container_app_environment_id = azurerm_container_app_environment.this.id
  resource_group_name          = azurerm_resource_group.rg.name
  revision_mode                = "Single"
  workload_profile_name        = "Consumption"

  identity {
    type = "SystemAssigned"
  }

  dynamic "secret" {
    for_each = local.martini_secrets
    content {
      name  = secret.key
      value = secret.value
    }
  }

  dynamic "registry" {
    for_each = local.designer_registry_credential != null ? [local.designer_registry_credential] : []
    content {
      server               = registry.value.server
      username             = registry.value.username
      password_secret_name = "registry-password"
    }
  }

  ingress {
    external_enabled           = true
    target_port                = local.designer_ui_port
    transport                  = "auto"
    allow_insecure_connections = false

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = 1
    max_replicas = 1

    container {
      name   = local.aci_service_name
      image  = "${local.aci_docker_image_url}:${var.martini_version}"
      cpu    = var.martini_cpu
      memory = "${var.martini_memory}Gi"

      command = [
        "sh",
        "-c",
        "node /home/martini/browser-app/lib/backend/main.js --hostname=0.0.0.0 --port=${local.designer_ui_port}",
      ]

      dynamic "env" {
        for_each = local.martini_designer_env_pairs
        content {
          name        = env.value.name
          value       = lookup(env.value, "value", null)
          secret_name = lookup(env.value, "secret_name", null)
        }
      }

      volume_mounts {
        name = "workspace-data"
        path = "/home/martini/martini-designer-workspace"
      }
      volume_mounts {
        name = "workspace-user"
        path = "/home/martini/.martini-designer"
      }
    }

    volume {
      name          = "workspace-data"
      storage_type  = "AzureFile"
      storage_name  = azurerm_container_app_environment_storage.this["workspace-data"].name
      mount_options = local.aca_mount_options
    }
    volume {
      name          = "workspace-user"
      storage_type  = "AzureFile"
      storage_name  = azurerm_container_app_environment_storage.this["workspace-user"].name
      mount_options = local.aca_mount_options
    }
  }

  tags = var.tags

  depends_on = [
    time_sleep.acs_smtp_role_propagation,
    terraform_data.ecr_image_import,
  ]
}

resource "azurerm_container_app_custom_domain" "martini" {
  count = local.bind_custom_domain && !var.enable_designer ? 1 : 0

  name             = var.custom_domain
  container_app_id = azurerm_container_app.martini[0].id

  lifecycle {
    # Registers the hostname with binding type Disabled; the SNI binding is
    # applied out-of-band by terraform_data.bind_custom_domain. The cert can't be
    # referenced here without a cycle — issuing it requires this hostname to exist.
    ignore_changes = [certificate_binding_type, container_app_environment_certificate_id]
  }
}

resource "azurerm_container_app_custom_domain" "martini_designer" {
  count = local.bind_custom_domain && var.enable_designer ? 1 : 0

  name             = var.custom_domain
  container_app_id = azurerm_container_app.martini_designer[0].id

  lifecycle {
    ignore_changes = [certificate_binding_type, container_app_environment_certificate_id]
  }
}

# Bind the issued managed certificate to the registered hostname via SNI. This
# can't be expressed on azurerm_container_app_custom_domain above: referencing
# the certificate there forms a cycle (cert depends_on the registration). The az
# CLI does a safe read-modify-write that preserves the rest of the ingress config.
resource "terraform_data" "bind_custom_domain" {
  count = local.bind_custom_domain ? 1 : 0

  triggers_replace = {
    app_id         = local.bound_app_id
    certificate_id = azurerm_container_app_environment_managed_certificate.custom[0].id
  }

  provisioner "local-exec" {
    command = <<-EOT
      az containerapp hostname bind \
        --resource-group "${azurerm_resource_group.rg.name}" \
        --name "${local.bound_app_name}" \
        --hostname "${var.custom_domain}" \
        --environment "${azurerm_container_app_environment.this.name}" \
        --certificate "${azurerm_container_app_environment_managed_certificate.custom[0].id}"
    EOT
  }
}
