resource "azurerm_container_group" "martini" {
  #checkov:skip=CKV2_AZURE_28:Managed Service Identity currently does not support container groups deployed in virtual networks.
  #checkov:skip=CKV_AZURE_235:Plaintext env vars carry non-secret tracker configuration; secrets use secure_environment_variables.
  count = var.enable_designer ? 0 : var.node_count

  name                = "${local.name_prefix}-aci-${count.index + 1}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  ip_address_type     = "Private"
  os_type             = "Linux"

  container {
    name   = local.aci_service_name
    image  = "${var.aci_docker_image_url}:${var.martini_version}"
    cpu    = var.cpu
    memory = var.memory

    security {
      privilege_enabled = false
    }

    ports {
      port = local.aci_container_port
    }

    environment_variables = var.enable_cassandra_tracker ? {
      MR_TRACKER_ENABLE_EMBEDDED_DATABASE = "false"
      MR_TRACKER_DATABASE_NAME            = "tracker"
    } : {}

    secure_environment_variables = {
      MR_LICENSE = azurerm_key_vault_secret.martini_workspace_license.value
    }

    volume {
      name                 = "db-pool"
      mount_path           = "${var.martini_home_path}/conf/db-pool"
      read_only            = false
      share_name           = azurerm_storage_share.db_pool.name
      storage_account_name = azurerm_storage_account.conf.name
      storage_account_key  = azurerm_storage_account.conf.primary_access_key
    }

    volume {
      name                 = "lib-ext"
      mount_path           = "${var.martini_home_path}/lib/ext"
      read_only            = false
      share_name           = azurerm_storage_share.runtime_lib_ext[0].name
      storage_account_name = azurerm_storage_account.conf.name
      storage_account_key  = azurerm_storage_account.conf.primary_access_key
    }

    volume {
      name                 = "conf-overrides"
      mount_path           = "${var.martini_home_path}/conf/overrides"
      read_only            = false
      share_name           = azurerm_storage_share.runtime_conf_overrides[0].name
      storage_account_name = azurerm_storage_account.conf.name
      storage_account_key  = azurerm_storage_account.conf.primary_access_key
    }

    volume {
      name                 = "packages"
      mount_path           = "${var.martini_home_path}/packages"
      read_only            = false
      share_name           = azurerm_storage_share.runtime_packages[0].name
      storage_account_name = azurerm_storage_account.conf.name
      storage_account_key  = azurerm_storage_account.conf.primary_access_key
    }
  }

  dynamic "image_registry_credential" {
    for_each = var.docker_registry_username != "" ? [1] : []

    content {
      server   = "index.docker.io"
      username = var.docker_registry_username
      password = var.docker_registry_password
    }
  }

  subnet_ids = [local.private_subnet_ids[count.index % length(local.private_subnet_ids)]]

  tags = var.tags
}

resource "azurerm_container_group" "martini_designer" {
  #checkov:skip=CKV2_AZURE_28:Managed Service Identity currently does not support container groups deployed in virtual networks.
  #checkov:skip=CKV_AZURE_235:Plaintext env vars carry non-secret tracker configuration; secrets use secure_environment_variables.
  count = var.enable_designer ? 1 : 0

  name                = "${local.name_prefix}-designer"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  ip_address_type     = "Private"
  os_type             = "Linux"

  container {
    name   = local.aci_service_name
    image  = "${var.designer_docker_image_url}:${var.martini_version}"
    cpu    = var.cpu
    memory = var.memory

    # Theia browser-app is not the image's default CMD. The sleep lets the
    # mounted Azure Files share and Martini runtime settle before Theia starts.
    commands = [
      "sh",
      "-c",
      "node /home/martini/browser-app/lib/backend/main.js --hostname=0.0.0.0 --port=${local.designer_ui_port}",
    ]

    security {
      privilege_enabled = false
    }

    ports {
      port = local.aci_container_port
    }

    ports {
      port = local.designer_ui_port
    }

    environment_variables = merge(
      {
        MARTINI_WORKSPACE            = "true"
        MR_SERVER_HTTP_PORT          = tostring(local.aci_container_port)
        MR_SERVER_DESIGNER_PORT      = tostring(local.designer_ui_port)
        MR_PACKAGE_PROPERTIES_PREFIX = "QA"
      },
      var.enable_cassandra_tracker ? {
        MR_TRACKER_ENABLE_EMBEDDED_DATABASE = "false"
        MR_TRACKER_DATABASE_NAME            = "tracker"
      } : {}
    )

    secure_environment_variables = {
      MR_LICENSE = azurerm_key_vault_secret.martini_workspace_license.value
    }

    volume {
      name                 = "workspace-data"
      mount_path           = "/home/martini/martini-designer-workspace"
      read_only            = false
      share_name           = azurerm_storage_share.designer_workspace_data[0].name
      storage_account_name = azurerm_storage_account.conf.name
      storage_account_key  = azurerm_storage_account.conf.primary_access_key
    }

    volume {
      name                 = "workspace-user"
      mount_path           = "/home/martini/.martini-designer"
      read_only            = false
      share_name           = azurerm_storage_share.designer_workspace_user[0].name
      storage_account_name = azurerm_storage_account.conf.name
      storage_account_key  = azurerm_storage_account.conf.primary_access_key
    }

    volume {
      name                 = "db-pool"
      mount_path           = "/home/martini/resources/martini-runtime/conf/db-pool"
      read_only            = false
      share_name           = azurerm_storage_share.db_pool.name
      storage_account_name = azurerm_storage_account.conf.name
      storage_account_key  = azurerm_storage_account.conf.primary_access_key
    }
  }

  dynamic "image_registry_credential" {
    for_each = var.docker_registry_username != "" ? [1] : []

    content {
      server   = "index.docker.io"
      username = var.docker_registry_username
      password = var.docker_registry_password
    }
  }

  subnet_ids = [local.private_subnet_ids[1]]

  tags = var.tags
}
