resource "random_password" "cassandra_admin" {
  count = var.enable_cassandra_tracker ? 1 : 0

  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# The Azure Cosmos DB first-party service principal needs permission to join
# the delegated subnet before the cluster can be created. Documented at
# https://aka.ms/ManagedCassandraVNetPermissions.
data "azuread_service_principal" "cosmos_db" {
  count = var.enable_cassandra_tracker ? 1 : 0

  client_id = "a232010e-820c-4083-83bb-3ace5fc29d0b"
}

resource "azurerm_role_assignment" "cassandra_cosmos_db_subnet_join" {
  count = var.enable_cassandra_tracker ? 1 : 0

  scope                = module.virtual_network.subnets["cassandra_subnet"].resource.id
  role_definition_name = "Network Contributor"
  principal_id         = data.azuread_service_principal.cosmos_db[0].object_id
}

# Azure RBAC has eventual-consistency propagation delays; the Cosmos DB
# control plane may not see the role assignment for 1-2 minutes after it's
# created. Without this buffer, cluster-create polls fail with BadRequest
# even though the assignment already exists.
resource "time_sleep" "wait_for_role_propagation" {
  count = var.enable_cassandra_tracker ? 1 : 0

  depends_on      = [azurerm_role_assignment.cassandra_cosmos_db_subnet_join]
  create_duration = "180s"
}

resource "azurerm_cosmosdb_cassandra_cluster" "tracker" {
  count = var.enable_cassandra_tracker ? 1 : 0

  name                           = "${local.name_prefix}-cassandra"
  resource_group_name            = azurerm_resource_group.rg.name
  location                       = azurerm_resource_group.rg.location
  delegated_management_subnet_id = module.virtual_network.subnets["cassandra_subnet"].resource.id
  default_admin_password         = random_password.cassandra_admin[0].result
  authentication_method          = "Cassandra"
  version                        = var.cassandra_version

  depends_on = [time_sleep.wait_for_role_propagation]

  # Azure never returns default_admin_password on reads, so after import it
  # appears as null in state and every subsequent plan wants to replace the
  # cluster. The field is also ForceNew in the provider, which would destroy
  # all keyspace data. Ignore it — password rotation has to be done out of
  # band (Azure portal / az CLI + a manual state-refresh of random_password).
  lifecycle {
    ignore_changes = [default_admin_password]
  }

  tags = merge(
    var.tags, {
      "Service" = "Cassandra"
    }
  )
}

resource "azurerm_cosmosdb_cassandra_datacenter" "tracker" {
  count = var.enable_cassandra_tracker ? 1 : 0

  name                           = "${local.name_prefix}-cassandra-dc"
  cassandra_cluster_id           = azurerm_cosmosdb_cassandra_cluster.tracker[0].id
  location                       = azurerm_resource_group.rg.location
  delegated_management_subnet_id = module.virtual_network.subnets["cassandra_subnet"].resource.id
  node_count                     = var.cassandra_node_count
  sku_name                       = var.cassandra_sku
  disk_count                     = var.cassandra_disk_count
  disk_sku                       = var.cassandra_disk_sku
}
