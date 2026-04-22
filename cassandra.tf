data "azurerm_public_ip" "nat_gw" {
  count = var.enable_cassandra_tracker ? 1 : 0

  name                = "${local.name_prefix}-nat-gw-public-ip"
  resource_group_name = azurerm_resource_group.rg.name
  depends_on          = [module.nat_gw]
}

resource "azurerm_cosmosdb_account" "cassandra" {
  count = var.enable_cassandra_tracker ? 1 : 0

  name                = "${local.name_prefix}-cassandra"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  capabilities {
    name = "EnableCassandra"
  }

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = azurerm_resource_group.rg.location
    failover_priority = 0
  }

  public_network_access_enabled = true
  # NAT GW egress IP (ACI outbound) + "0.0.0.0" sentinel. The sentinel is Azure's documented
  # "Accept connections from within Azure datacenters" marker: it permits requests from any
  # Azure datacenter IP range (including other tenants' subscriptions), still gated by the
  # account's auth token. It does not open access to arbitrary internet IPs.
  # https://learn.microsoft.com/en-us/azure/cosmos-db/how-to-configure-firewall#allow-requests-from-global-azure-datacenters-or-other-sources-within-azure
  ip_range_filter = toset([
    data.azurerm_public_ip.nat_gw[0].ip_address,
    "0.0.0.0",
  ])

  tags = merge(
    var.tags, {
      "Service" = "Cassandra"
    }
  )
}

resource "azurerm_cosmosdb_cassandra_keyspace" "tracker" {
  count = var.enable_cassandra_tracker ? 1 : 0

  name                = var.cassandra_keyspace_name
  resource_group_name = azurerm_resource_group.rg.name
  account_name        = azurerm_cosmosdb_account.cassandra[0].name
  throughput          = var.cassandra_throughput
}
