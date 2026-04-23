resource "azurerm_container_group" "martini" {
  #checkov:skip=CKV2_AZURE_28:Managed Service Identity currently does not support container groups deployed in virtual networks.
  #checkov:skip=CKV_AZURE_235:Plaintext env vars carry non-secret tracker configuration; secrets use secure_environment_variables.
  count = var.node_count

  name                = "${local.name_prefix}-aci-${count.index + 1}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  ip_address_type     = "Private"
  os_type             = "Linux"

  container {
    name   = local.aci_service_name
    image  = "${var.aci_docker_image_url}:${var.martini_runtime_version}"
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

    # Sub-path mount so the rest of the image's /data/conf tree (log4j2.template,
    # application.properties, ...) stays intact. Azure Files is writable and
    # persistent across restarts, so Martini-added *.dbxml files survive.
    dynamic "volume" {
      for_each = var.enable_cassandra_tracker ? [1] : []

      content {
        name                 = "tracker-db-pool"
        mount_path           = "${var.martini_home_path}/conf/db-pool"
        read_only            = false
        share_name           = azurerm_storage_share.conf_db_pool[0].name
        storage_account_name = azurerm_storage_account.conf[0].name
        storage_account_key  = azurerm_storage_account.conf[0].primary_access_key
      }
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
