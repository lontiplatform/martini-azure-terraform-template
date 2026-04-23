resource "random_password" "cassandra_admin" {
  count = var.enable_cassandra_tracker ? 1 : 0

  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
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
