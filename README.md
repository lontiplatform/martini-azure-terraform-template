# Martini Terraform Template

The repository contains a Terraform template to create a complete infrastructure running Martini Runtime in the cloud 
on Azure ACI along with optional dependency such as an SQL database.

# Requirements

The template requires an installed Terraform with version 1.6.0 or higher. In order to install the Terraform, please 
use instructions from [the Terraform site](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli)

The template also assumes that you have an existing Azure account and credentials for using the account installed locally.
In order to install the credentials locally, please use instructions from [the Azure site](https://learn.microsoft.com/en-us/cli/azure/authenticate-azure-cli?view=azure-cli-latest)

# How to use this template

In order to deploy the environment to the cloud, please run following commands:

- `terraform init`
- `terraform apply -var-file=example.tfvars`

# Cost estimation

> _The figures below are **estimates only** and may differ for the end user. They are retail pay-as-you-go list prices for the **East US** region, sourced from the [Azure Retail Prices API](https://learn.microsoft.com/en-us/rest/api/cost-management/retail-prices/azure-retail-prices) on **2026-05-12**. Actual cost depends on region, traffic volume, storage growth, EA / CSP discounts, and price changes after that date. Bandwidth / egress, backup, and diagnostic-log retention are **not** included unless noted. Always cross-check with the [Azure Pricing Calculator](https://azure.microsoft.com/en-us/pricing/calculator/) before committing budget._

## Always-on baseline (Mode A, no optional flag set)

Costs that apply to every deployment with the defaults in `variables.tf`. Monthly figures assume 730 hours.

| Resource | SKU / size | Unit price | Est. monthly (USD) |
|---|---|---|---|
| [Application Gateway](https://azure.microsoft.com/en-us/pricing/details/application-gateway/) | Standard_v2, capacity 2 | $0.20/h fixed + 2 × $0.008/h capacity unit | **~$157.68** |
| [Public IP](https://azure.microsoft.com/en-us/pricing/details/ip-addresses/) | Standard Static IPv4 | $0.005/h | **~$3.65** |
| [NAT Gateway](https://azure.microsoft.com/en-us/pricing/details/azure-nat-gateway/) | Standard | $0.045/h resource + $0.045/GB data processed | **~$32.85** (+ data) |
| [Container Instances](https://azure.microsoft.com/en-us/pricing/details/container-instances/) — 1× Martini runtime | 2 vCPU + 4 GB, Linux | $0.0405/vCPU-h + $0.00445/GB-h | **~$72.13** |
| [Key Vault](https://azure.microsoft.com/en-us/pricing/details/key-vault/) | Standard | $0.03 per 10K operations | **< $1** (ops-only) |
| [Storage Account — Files](https://azure.microsoft.com/en-us/pricing/details/storage/files/) | Standard LRS, transaction-optimized | $0.06/GB-month for used data + per-op | **~$1–3** (low usage) |
| Virtual Network / NSG / Route Table | n/a | free | $0 |
| **Baseline total** | | | **≈ $267 / month** |

## Optional flag deltas

Each row is **on top of** the baseline. Combine them for your configuration.

| Flag | What it adds | Est. delta (USD/month) |
|---|---|---|
| `enable_designer = true` | Swaps the runtime ACI for a single Designer ACI at the same `martini_cpu` / `martini_memory`; provisions larger storage shares (billed by actual usage, not quota). | **~$0** (no extra compute; storage delta negligible at low usage) |
| `enable_sql_server = true` | [Azure SQL Database Single, Standard S0](https://azure.microsoft.com/en-us/pricing/details/azure-sql-database/single/) (10 DTU) @ $0.4839/day — includes up to 250 GB storage. | **+~$14.71** |
| `enable_cassandra_tracker = true` | [Azure Managed Instance for Apache Cassandra](https://azure.microsoft.com/en-us/pricing/details/managed-instance-apache-cassandra/): 3× `Standard_D8s_v5` nodes @ $0.48/h + 3× [P30 premium disks](https://azure.microsoft.com/en-us/pricing/details/managed-disks/) @ $135.17/mo + Cassandra backup @ $0.10/GB-mo. | **+~$1,457** |
| `enable_event_hub = true` | [Event Hubs](https://azure.microsoft.com/en-us/pricing/details/event-hubs/) Basic namespace + 1 throughput unit @ $0.015/h, plus $0.028 per 1 M ingress events. | **+~$11** (+ event volume) |
| `existing_vnet = { ... }` (Mode B) | Skips the NAT Gateway, shared route table, and shared NSG owned by this template — outbound NAT becomes your VNet's responsibility. | **−~$32.85** (saves NAT Gateway) |

## Scaling levers

How the numeric inputs in `variables.tf` move the cost lines above:

- **`martini_node_count = N`** (runtime mode only) — multiplies the [Container Instances](https://azure.microsoft.com/en-us/pricing/details/container-instances/) line by `N`. At defaults that's ≈ **+$72/month per extra replica**.
- **`martini_cpu` / `martini_memory`** — ACI is billed per vCPU-second and per GB-second. Monthly cost per replica is `(martini_cpu × $0.0405 + martini_memory × $0.00445) × 730`.
- **`cassandra_sku`** — list ranges from `Standard_D8s_v5` (**$0.48/h/node**, the default and cheapest accepted SKU) to `Standard_E32s_v5` (**$2.52/h/node**); picking a larger SKU can multiply the Cassandra compute line by up to ~5×.
- **`cassandra_node_count`** — linear multiplier; minimum 3.
- **`cassandra_disk_count` / `cassandra_disk_sku`** — each [P30 disk](https://azure.microsoft.com/en-us/pricing/details/managed-disks/) is $135.17/mo; bumping to P40 ($270.34/mo) or adding disks per node multiplies the disk line accordingly.
- **`event_hub_namespace_sku`** — Basic → Standard moves the throughput-unit price from **$0.015/h** to **$0.03/h** and unlocks features billed separately (Capture $0.10/h, Kafka endpoint $0.09/h).
- **`event_hub_capacity`** — linear multiplier on the throughput-unit line.
- **`sql_max_size_gb`** — S0 already includes 250 GB; raising this stays free up to that ceiling. Going past 250 GB requires a higher SQL SKU than S0.

# Bring-your-own VNet (Mode B)

By default the template provisions a fresh VNet plus a NAT gateway, route table, and shared NSG. To deploy into an existing corporate VNet instead, set `existing_vnet` and supply CIDRs for the three workload subnets (`aci`, `appgw`, and — if `enable_cassandra_tracker = true` — `cassandra`):

```hcl
existing_vnet = {
  name                = "vnet-DevCentralUS"
  resource_group_name = "network"
}

aci_subnet_cidr       = "172.16.3.16/28"
appgw_subnet_cidr     = "172.16.3.64/26"  # /26 minimum for Application Gateway v2
cassandra_subnet_cidr = "172.16.3.192/26" # /26 minimum for Managed Cassandra

# Optional: associate the new ACI / Cassandra subnets with the network team's
# shared route table and NSG. The Application Gateway subnet always gets a
# dedicated NSG created by this template.
byo_vnet_route_table_id  = "/subscriptions/.../routeTables/Route-Dev-Prd"
byo_vnet_workload_nsg_id = "/subscriptions/.../networkSecurityGroups/nsg-cus-dev-network"
```

In Mode B the template:

- creates `azurerm_subnet.aci` (delegated to `Microsoft.ContainerInstance/containerGroups`), `azurerm_subnet.appgw`, and `azurerm_subnet.cassandra` (delegated to `Microsoft.DocumentDB/cassandraClusters`) inside `existing_vnet.name`
- creates a dedicated NSG for the App Gateway subnet (`AllowAppGatewayInfraPorts` and `AllowClientToAppGateway` inbound)
- does **not** create a NAT gateway, route table, or shared NSG

The Terraform principal must hold `Microsoft.Network/virtualNetworks/subnets/write` on the existing VNet. Two caveats worth checking with whoever owns that VNet:

- their VNet's Terraform must not declare inline `subnet { ... }` blocks on `azurerm_virtual_network` (this would delete our subnets on their next apply); they should manage subnets via standalone `azurerm_subnet` resources or `lifecycle { ignore_changes = [subnet] }`.
- if you set `byo_vnet_workload_nsg_id` to a shared NSG, that NSG's existing rules must permit traffic from the AppGW subnet CIDR to the ACI subnet on the Designer/Runtime port (`8080` or `3000`); otherwise AppGW health probes fail. Leaving `byo_vnet_workload_nsg_id = null` keeps the ACI subnet on Azure's default `AllowVnetInBound`, which already covers this.

# Uses external modules

The repository uses external Terraform modules in order to configure some components in the cloud. Please find the list of modules below

# Azure SQL Change Event Streaming → Event Hubs

Azure SQL [Change Event Streaming (CES)](https://learn.microsoft.com/en-us/sql/relational-databases/track-changes/change-event-streaming/overview) is a public-preview feature that streams row-level INSERT/UPDATE/DELETE events from an Azure SQL database directly into Azure Event Hubs as CloudEvents. Setting `enable_event_hub = true` provisions the Event Hubs namespace and the hub instances you list. The source SQL Server's system-assigned managed identity is granted `Azure Event Hubs Data Sender` on each hub — by default this is the server identified in `ces_source_sql_server`, falling back to the local `module.sql_server` when that variable is null and `enable_sql_server = true`. CES itself is configured per-database in T-SQL — Terraform only delivers the destination and the trust relationship.

## Provision the destination

```hcl
enable_event_hub        = true
event_hub_namespace_sku = "Standard"
event_hub_capacity      = 1

event_hubs = {
  martini-ces = {
    partition_count   = 4
    message_retention = 1
  }
}

ces_source_sql_server = {
  name                = "<external-sql-server-name>"
  resource_group_name = "<external-sql-resource-group>"
}
```

The SQL Server named in `ces_source_sql_server` must already exist before `terraform apply` and must have system-assigned managed identity enabled — the lookup uses `data.azurerm_mssql_server` against the same subscription this template deploys to. Omit `ces_source_sql_server` to fall back to the local SQL Server (when `enable_sql_server = true`), or to skip the role assignment entirely.

`terraform apply`. The `event_hub_namespace_fqdn` output and the `event-hub-namespace-fqdn` Key Vault secret are what the T-SQL bootstrap below references.

## One-time T-SQL bootstrap

CES tables, stream groups, and credentials are objects inside the database, not Azure resources, so they are not provisioned by this template. Connect to the `martini` database with a `db_owner` login (the SQL admin in Key Vault works) and run:

```sql
USE [martini];

-- Master key encrypts the database-scoped credential. Choose any strong
-- password; you will not need to use it again.
CREATE MASTER KEY ENCRYPTION BY PASSWORD = '<strong-password>';

-- 'Managed Identity' tells Azure SQL DB to authenticate to Event Hubs as the
-- SQL Server's system-assigned identity, which Terraform has already granted
-- Azure Event Hubs Data Sender on the hub.
CREATE DATABASE SCOPED CREDENTIAL ces_eh
    WITH IDENTITY = 'Managed Identity';

EXEC sys.sp_enable_event_stream;

EXEC sys.sp_create_event_stream_group
    @stream_group_name      = N'martini_ces',
    @destination_type       = N'AzureEventHubsAmqp',
    @destination_location   = N'<event_hub_namespace_fqdn>/<hub-name>',
    @destination_credential = ces_eh,
    @max_message_size_kb    = 256,
    @partition_key_scheme   = N'None';

-- Repeat for each table you want to stream.
EXEC sys.sp_add_object_to_event_stream_group
    N'martini_ces', N'dbo.<table>';
```

`sys.sp_help_change_feed_settings` and the `sys.dm_change_feed_errors` DMV report stream state and delivery errors.

## Compatibility caveats

CES preview has hard constraints worth knowing before designing the schema you intend to stream:

- Per-table: clustered columnstore indexes, temporal/ledger history tables, Always Encrypted, in-memory OLTP, graph tables, and external tables are **not** supported.
- Per-column: `geography`, `geometry`, `image`, `json`, `rowversion`/`timestamp`, `sql_variant`, `text`/`ntext`, `vector`, `xml`, and UDT columns are **silently skipped** in events.
- A database with CES enabled cannot also have CDC, transactional replication, Synapse Link, or a Fabric Mirrored configuration. Change Tracking is fine.
- Renaming a streamed table or column fails until you remove it from the stream group.
- CES streams to Event Hubs **public endpoints only** in preview — service endpoints / private endpoints are not supported. The namespace this template creates is therefore public-network-enabled by design.
- Pre-existing rows are not seeded; only changes after `sp_enable_event_stream` are emitted.

## Consumer-side wiring

Whenever `enable_event_hub = true` and `event_hubs` has at least one entry, the active Martini ACI (runtime when `enable_designer = false`, otherwise Designer) is wired up as an Event Hubs consumer:

- Each container group runs with a system-assigned managed identity. With `local_authentication_enabled = false` on the namespace, this is the only auth posture available — SAS connection strings are not an option.
- Each MI is granted `Azure Event Hubs Data Receiver` on every hub in `event_hubs`. In runtime mode with `martini_node_count = N`, this is `N × len(event_hubs)` assignments — one per (replica, hub) pair so each replica's identity can read independently.
- All consumers read from the implicit `$Default` consumer group. Basic-tier namespaces don't permit custom consumer groups, and the runtime fan-out works on `$Default` too — Event Hubs load-balances partitions across all consumers in the group regardless of name.
- The container receives three plaintext env vars so it can connect without manual config: `MR_EVENT_HUB_NAMESPACE_FQDN`, `MR_EVENT_HUB_NAMES` (comma-separated), and `MR_EVENT_HUB_CONSUMER_GROUP` (always `$Default`).
- A 5-minute `time_sleep` after the role assignments lets RBAC propagate before the container's first connect — Event Hubs rejects auth for 1-2 minutes after a grant.

# Precommit checks

The template uses [pre-commit](https://github.com/antonbabenko/pre-commit-terraform#how-to-install) library in order to 
run a few checks before the commit. The checks used are (in order of execution):

- [Checkov](https://github.com/bridgecrewio/checkov)
- `terraform fmt`
- [Terraform Docs](https://github.com/terraform-docs/terraform-docs)
- `terraform validate`

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_azuread"></a> [azuread](#requirement\_azuread) | ~> 3.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | ~> 4.38 |
| <a name="requirement_local"></a> [local](#requirement\_local) | ~> 2.5 |
| <a name="requirement_pkcs12"></a> [pkcs12](#requirement\_pkcs12) | ~> 0.2 |
| <a name="requirement_time"></a> [time](#requirement\_time) | ~> 0.12 |
| <a name="requirement_tls"></a> [tls](#requirement\_tls) | ~> 4.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azuread"></a> [azuread](#provider\_azuread) | 3.8.0 |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | 4.71.0 |
| <a name="provider_local"></a> [local](#provider\_local) | 2.8.0 |
| <a name="provider_pkcs12"></a> [pkcs12](#provider\_pkcs12) | 0.4.0 |
| <a name="provider_random"></a> [random](#provider\_random) | 3.8.1 |
| <a name="provider_time"></a> [time](#provider\_time) | 0.13.1 |
| <a name="provider_tls"></a> [tls](#provider\_tls) | 4.2.1 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_app_gw"></a> [app\_gw](#module\_app\_gw) | Azure/avm-res-network-applicationgateway/azurerm | ~> 0.4.2 |
| <a name="module_nat_gw"></a> [nat\_gw](#module\_nat\_gw) | Azure/avm-res-network-natgateway/azurerm | ~> 0.2.1 |
| <a name="module_network_sg"></a> [network\_sg](#module\_network\_sg) | Azure/avm-res-network-networksecuritygroup/azurerm | ~> 0.5.0 |
| <a name="module_route_table"></a> [route\_table](#module\_route\_table) | Azure/avm-res-network-routetable/azurerm | ~> 0.4.1 |
| <a name="module_sql_server"></a> [sql\_server](#module\_sql\_server) | Azure/avm-res-sql-server/azurerm | ~> 0.1.5 |
| <a name="module_virtual_network"></a> [virtual\_network](#module\_virtual\_network) | Azure/avm-res-network-virtualnetwork/azurerm | ~> 0.9.3 |

## Resources

| Name | Type |
|------|------|
| [azurerm_container_group.martini](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/container_group) | resource |
| [azurerm_container_group.martini_designer](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/container_group) | resource |
| [azurerm_cosmosdb_cassandra_cluster.tracker](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/cosmosdb_cassandra_cluster) | resource |
| [azurerm_cosmosdb_cassandra_datacenter.tracker](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/cosmosdb_cassandra_datacenter) | resource |
| [azurerm_eventhub.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/eventhub) | resource |
| [azurerm_eventhub_namespace.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/eventhub_namespace) | resource |
| [azurerm_key_vault.key_vault](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault) | resource |
| [azurerm_key_vault_secret.cassandra_admin_password](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_secret) | resource |
| [azurerm_key_vault_secret.cassandra_contact_point](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_secret) | resource |
| [azurerm_key_vault_secret.event_hub_names](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_secret) | resource |
| [azurerm_key_vault_secret.event_hub_namespace_fqdn](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_secret) | resource |
| [azurerm_key_vault_secret.martini_workspace_license](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_secret) | resource |
| [azurerm_key_vault_secret.sql_admin_password](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_secret) | resource |
| [azurerm_key_vault_secret.sql_admin_username](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_secret) | resource |
| [azurerm_network_security_group.appgw](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_security_group) | resource |
| [azurerm_public_ip.app_gw_pip](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/public_ip) | resource |
| [azurerm_resource_group.rg](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group) | resource |
| [azurerm_role_assignment.cassandra_cosmos_db_subnet_join](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.ces_azure_sql_to_eh](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.martini_designer_eh_receiver](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.martini_runtime_eh_receiver](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_storage_account.conf](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_account) | resource |
| [azurerm_storage_share.db_pool](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_share) | resource |
| [azurerm_storage_share.designer_workspace_data](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_share) | resource |
| [azurerm_storage_share.designer_workspace_user](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_share) | resource |
| [azurerm_storage_share.runtime_conf_overrides](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_share) | resource |
| [azurerm_storage_share.runtime_lib_ext](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_share) | resource |
| [azurerm_storage_share.runtime_packages](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_share) | resource |
| [azurerm_storage_share_directory.designer_runtime_conf](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_share_directory) | resource |
| [azurerm_storage_share_directory.designer_runtime_db_pool](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_share_directory) | resource |
| [azurerm_storage_share_file.designer_tracker_dbxml](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_share_file) | resource |
| [azurerm_storage_share_file.designer_version](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_share_file) | resource |
| [azurerm_storage_share_file.tracker_dbxml](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_share_file) | resource |
| [azurerm_subnet.aci](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet) | resource |
| [azurerm_subnet.appgw](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet) | resource |
| [azurerm_subnet.cassandra](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet) | resource |
| [azurerm_subnet_network_security_group_association.aci](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet_network_security_group_association) | resource |
| [azurerm_subnet_network_security_group_association.appgw](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet_network_security_group_association) | resource |
| [azurerm_subnet_network_security_group_association.cassandra](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet_network_security_group_association) | resource |
| [azurerm_subnet_route_table_association.aci](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet_route_table_association) | resource |
| [azurerm_subnet_route_table_association.cassandra](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet_route_table_association) | resource |
| [local_file.designer_version](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.tracker_dbxml](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [pkcs12_from_pem.app_gw](https://registry.terraform.io/providers/chilicat/pkcs12/latest/docs/resources/from_pem) | resource |
| [random_password.admin_password](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [random_password.app_gw_pfx](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [random_password.cassandra_admin](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [random_string.kv_suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [random_string.pip_dns_suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [random_string.storage_suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [time_sleep.ces_role_propagation](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/sleep) | resource |
| [time_sleep.martini_eh_role_propagation](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/sleep) | resource |
| [time_sleep.wait_for_cluster_settle](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/sleep) | resource |
| [time_sleep.wait_for_role_propagation](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/sleep) | resource |
| [tls_private_key.app_gw](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/private_key) | resource |
| [tls_self_signed_cert.app_gw](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/self_signed_cert) | resource |
| [azuread_service_principal.cosmos_db](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/data-sources/service_principal) | data source |
| [azurerm_client_config.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |
| [azurerm_mssql_server.ces_source](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/mssql_server) | data source |
| [azurerm_virtual_network.existing](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/virtual_network) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_aci_subnet_cidr"></a> [aci\_subnet\_cidr](#input\_aci\_subnet\_cidr) | CIDR for the ACI delegated subnet inside the existing VNet. Required when existing\_vnet is set; ignored otherwise. | `string` | `null` | no |
| <a name="input_appgw_subnet_cidr"></a> [appgw\_subnet\_cidr](#input\_appgw\_subnet\_cidr) | CIDR for the Application Gateway dedicated subnet inside the existing VNet (/26 or larger recommended for v2). Required when existing\_vnet is set; ignored otherwise. | `string` | `null` | no |
| <a name="input_byo_vnet_route_table_id"></a> [byo\_vnet\_route\_table\_id](#input\_byo\_vnet\_route\_table\_id) | Optional ID of a pre-existing route table to associate with the ACI and Cassandra subnets when existing\_vnet is set. Leave null to use Azure system routes. Ignored when existing\_vnet is null. | `string` | `null` | no |
| <a name="input_byo_vnet_workload_nsg_id"></a> [byo\_vnet\_workload\_nsg\_id](#input\_byo\_vnet\_workload\_nsg\_id) | Optional ID of a pre-existing NSG to associate with the ACI and Cassandra subnets when existing\_vnet is set. The Application Gateway subnet always gets a dedicated NSG created by this template. Ignored when existing\_vnet is null. | `string` | `null` | no |
| <a name="input_cassandra_disk_count"></a> [cassandra\_disk\_count](#input\_cassandra\_disk\_count) | Number of premium managed disks attached to each Cassandra node. Valid only if `enable_cassandra_tracker` is set to `true`. | `number` | `1` | no |
| <a name="input_cassandra_disk_sku"></a> [cassandra\_disk\_sku](#input\_cassandra\_disk\_sku) | Premium disk SKU for each Cassandra node disk (e.g. `P30`, `P40`). Valid only if `enable_cassandra_tracker` is set to `true`. | `string` | `"P30"` | no |
| <a name="input_cassandra_node_count"></a> [cassandra\_node\_count](#input\_cassandra\_node\_count) | Number of Cassandra nodes per data center. Azure Managed Instance for Apache Cassandra requires at least 3. Valid only if `enable_cassandra_tracker` is set to `true`. | `number` | `3` | no |
| <a name="input_cassandra_sku"></a> [cassandra\_sku](#input\_cassandra\_sku) | VM SKU for each Cassandra node. Azure Managed Cassandra only accepts a fixed list of 8-core-and-larger SKUs (see validation). Default `Standard_D8s_v5` is the cheapest supported option for dev/demo; use `Standard_E8s_v5` or larger for production. | `string` | `"Standard_D8s_v5"` | no |
| <a name="input_cassandra_subnet_cidr"></a> [cassandra\_subnet\_cidr](#input\_cassandra\_subnet\_cidr) | CIDR for the delegated subnet hosting Azure Managed Instance for Apache Cassandra. Must be /26 or larger. Valid only if `enable_cassandra_tracker` is set to `true`. | `string` | `"10.0.20.0/26"` | no |
| <a name="input_cassandra_version"></a> [cassandra\_version](#input\_cassandra\_version) | Apache Cassandra major version for the Managed Instance cluster. Valid only if `enable_cassandra_tracker` is set to `true`. | `string` | `"4.0"` | no |
| <a name="input_ces_source_sql_server"></a> [ces\_source\_sql\_server](#input\_ces\_source\_sql\_server) | Azure SQL Server (in the same subscription) whose system-assigned managed identity is granted `Azure Event Hubs Data Sender` on each hub. The server must already exist at apply time and have system-assigned MI enabled. Set to `null` to fall back to the local `module.sql_server` (when `enable_sql_server = true`) or to skip the role assignment entirely. Valid only if `enable_event_hub` is set to `true`. | <pre>object({<br/>    name                = string<br/>    resource_group_name = string<br/>  })</pre> | `null` | no |
| <a name="input_docker_registry_password"></a> [docker\_registry\_password](#input\_docker\_registry\_password) | Docker Hub access token (preferred) or password paired with `docker_registry_username`. | `string` | `""` | no |
| <a name="input_docker_registry_username"></a> [docker\_registry\_username](#input\_docker\_registry\_username) | Docker Hub username used to authenticate image pulls and avoid anonymous rate limits. Leave empty to pull anonymously. | `string` | `""` | no |
| <a name="input_enable_cassandra_tracker"></a> [enable\_cassandra\_tracker](#input\_enable\_cassandra\_tracker) | Should Martini use Azure Managed Instance for Apache Cassandra as the tracker backend? | `bool` | `false` | no |
| <a name="input_enable_designer"></a> [enable\_designer](#input\_enable\_designer) | Deploy Martini Designer as a single-instance ACI instead of the runtime. Mutually exclusive with the runtime deployment. | `bool` | `false` | no |
| <a name="input_enable_event_hub"></a> [enable\_event\_hub](#input\_enable\_event\_hub) | Provision an Azure Event Hubs namespace and the hub instances declared in `event_hubs` as the destination for Azure SQL Change Event Streaming (CES). The source SQL Server is identified by `ces_source_sql_server`; if that variable is null and `enable_sql_server = true`, the local SQL Server's system-assigned managed identity is used as fallback. Otherwise the namespace is created with no role assignment. | `bool` | `false` | no |
| <a name="input_enable_sql_server"></a> [enable\_sql\_server](#input\_enable\_sql\_server) | Should Martini use SQL Server database? | `bool` | `false` | no |
| <a name="input_event_hub_capacity"></a> [event\_hub\_capacity](#input\_event\_hub\_capacity) | Throughput units (Standard) or processing units (Premium) for the namespace. Ignored for Basic. Valid only if `enable_event_hub` is set to `true`. | `number` | `1` | no |
| <a name="input_event_hub_namespace_sku"></a> [event\_hub\_namespace\_sku](#input\_event\_hub\_namespace\_sku) | SKU tier for the Event Hubs namespace. Valid only if `enable_event_hub` is set to `true`. | `string` | `"Basic"` | no |
| <a name="input_event_hubs"></a> [event\_hubs](#input\_event\_hubs) | Event Hub instances to create on the namespace, keyed by name. Each entry sets `partition_count` and `message_retention` (days). Each hub receives an `Azure Event Hubs Data Sender` grant for the resolved CES source identity (see `ces_source_sql_server`), if any. Valid only if `enable_event_hub` is set to `true`. | <pre>map(object({<br/>    partition_count   = number<br/>    message_retention = number<br/>  }))</pre> | `{}` | no |
| <a name="input_existing_vnet"></a> [existing\_vnet](#input\_existing\_vnet) | Reference to a pre-existing VNet to deploy workload subnets into. When set,<br/>the template skips creating its own VNet/NAT/route-table/shared NSG and<br/>instead creates the per-workload subnets (ACI, App Gateway, and — when<br/>enable\_cassandra\_tracker = true — Cassandra MI) directly inside the named<br/>VNet via azurerm\_subnet. The Terraform principal must hold<br/>Microsoft.Network/virtualNetworks/subnets/write on the VNet.<br/><br/>When null (default), the template creates a brand-new VNet plus NAT gateway,<br/>route table, and shared NSG using vnet\_address\_space / public\_subnet\_cidrs /<br/>private\_subnet\_cidrs / cassandra\_subnet\_cidr (current behaviour, preserved). | <pre>object({<br/>    name                = string<br/>    resource_group_name = string<br/>  })</pre> | `null` | no |
| <a name="input_martini_cpu"></a> [martini\_cpu](#input\_martini\_cpu) | Number of CPU cores to allocate for the application. | `number` | `2` | no |
| <a name="input_martini_home_path"></a> [martini\_home\_path](#input\_martini\_home\_path) | Path to the Martini workspace inside the container image. Default matches the official lontiplatform/martini-server-runtime image. | `string` | `"/data"` | no |
| <a name="input_martini_memory"></a> [martini\_memory](#input\_martini\_memory) | Amount of memory (in GB) to allocate for the application | `number` | `4` | no |
| <a name="input_martini_node_count"></a> [martini\_node\_count](#input\_martini\_node\_count) | Number of Martini container instances to run behind the Application Gateway | `number` | `1` | no |
| <a name="input_martini_version"></a> [martini\_version](#input\_martini\_version) | Tag of the Martini Docker image to deploy. Applied to the runtime image or the designer image depending on `enable_designer`. | `string` | `"2.7.2"` | no |
| <a name="input_martini_workspace_license"></a> [martini\_workspace\_license](#input\_martini\_workspace\_license) | Full license text to be used with Martini | `string` | n/a | yes |
| <a name="input_name_suffix"></a> [name\_suffix](#input\_name\_suffix) | Suffix to add to the resources' names | `string` | `""` | no |
| <a name="input_private_subnet_cidrs"></a> [private\_subnet\_cidrs](#input\_private\_subnet\_cidrs) | Mode A only — ignored when existing\_vnet is set. A list of prefixes for private subnets. | `list(string)` | <pre>[<br/>  "10.0.11.0/24",<br/>  "10.0.12.0/24"<br/>]</pre> | no |
| <a name="input_public_subnet_cidrs"></a> [public\_subnet\_cidrs](#input\_public\_subnet\_cidrs) | Mode A only — ignored when existing\_vnet is set. A list of prefixes for public subnets. | `list(string)` | <pre>[<br/>  "10.0.1.0/24",<br/>  "10.0.2.0/24"<br/>]</pre> | no |
| <a name="input_rg_location"></a> [rg\_location](#input\_rg\_location) | Azure region to deploy resources into | `string` | n/a | yes |
| <a name="input_sql_database_name"></a> [sql\_database\_name](#input\_sql\_database\_name) | Name of the SQL database. Valid only if `enable_sql_server` is set to `true` | `string` | `"martini"` | no |
| <a name="input_sql_max_size_gb"></a> [sql\_max\_size\_gb](#input\_sql\_max\_size\_gb) | The max size of the database in gigabytes. | `number` | `50` | no |
| <a name="input_sql_server_admin_username"></a> [sql\_server\_admin\_username](#input\_sql\_server\_admin\_username) | Username to set in the SQl Server. Valid only if `enable_sql_server` is set to `true` | `string` | `null` | no |
| <a name="input_sql_server_version"></a> [sql\_server\_version](#input\_sql\_server\_version) | The RDS engine version to use. Valid only if `enable_sql_server` is set to `true` | `string` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Common tags for components created in the infrastructure | `map(string)` | <pre>{<br/>  "Application": "Martini",<br/>  "Repository": "https://github.com/lontiplatform/martini-azure-terraform-template"<br/>}</pre> | no |
| <a name="input_vnet_address_space"></a> [vnet\_address\_space](#input\_vnet\_address\_space) | Mode A only — ignored when existing\_vnet is set. Virtual Network CIDR | `list(string)` | <pre>[<br/>  "10.0.0.0/18"<br/>]</pre> | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_app_gw_public_ip"></a> [app\_gw\_public\_ip](#output\_app\_gw\_public\_ip) | n/a |
| <a name="output_app_gw_url"></a> [app\_gw\_url](#output\_app\_gw\_url) | n/a |
| <a name="output_cassandra_cluster_name"></a> [cassandra\_cluster\_name](#output\_cassandra\_cluster\_name) | n/a |
| <a name="output_cassandra_contact_point"></a> [cassandra\_contact\_point](#output\_cassandra\_contact\_point) | n/a |
| <a name="output_cassandra_port"></a> [cassandra\_port](#output\_cassandra\_port) | n/a |
| <a name="output_event_hub_names"></a> [event\_hub\_names](#output\_event\_hub\_names) | n/a |
| <a name="output_event_hub_namespace_fqdn"></a> [event\_hub\_namespace\_fqdn](#output\_event\_hub\_namespace\_fqdn) | n/a |
| <a name="output_event_hub_namespace_name"></a> [event\_hub\_namespace\_name](#output\_event\_hub\_namespace\_name) | n/a |
| <a name="output_resource_group_location"></a> [resource\_group\_location](#output\_resource\_group\_location) | n/a |
| <a name="output_resource_group_name"></a> [resource\_group\_name](#output\_resource\_group\_name) | n/a |
| <a name="output_subnet_prefixes"></a> [subnet\_prefixes](#output\_subnet\_prefixes) | n/a |
<!-- END_TF_DOCS -->