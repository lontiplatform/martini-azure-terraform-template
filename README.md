# Martini Terraform Template

The repository contains a Terraform template to create a complete infrastructure running Martini Runtime in the cloud 
on Azure ACI along with optional dependency such as an SQL database.

# Breaking change: Cassandra backend switched to Managed Instance

`enable_cassandra_tracker = true` now provisions an **Azure Managed Instance for Apache Cassandra** cluster, not Cosmos DB with the Cassandra API. The two are different Azure resource types with no `moved {}` migration path — a `terraform apply` over a previous Cosmos-based deployment will **destroy** the Cosmos account and its keyspace data and **create** a new MI cluster in their place. Any data in the old keyspace is lost.

MI cluster provisioning takes approximately 20–40 minutes. The minimum cluster is 3 nodes × `Standard_E2s_v5` + 4 × P30 disks per node — significantly more expensive than the Cosmos 400 RU/s minimum. Adjust `cassandra_sku`, `cassandra_node_count`, `cassandra_disk_count`, `cassandra_disk_sku` for your workload.

# Requirements

The template requires an installed Terraform with version 1.6.0 or higher. In order to install the Terraform, please 
use instructions from [the Terraform site](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli)

The template also assumes that you have an existing Azure account and credentials for using the account installed locally.
In order to install the credentials locally, please use instructions from [the Azure site](https://learn.microsoft.com/en-us/cli/azure/authenticate-azure-cli?view=azure-cli-latest)

# How to use this template

In order to deploy the environment to the cloud, please run following commands:

- `terraform init`
- `terraform apply -var-file=example.tfvars`

# Uses external modules

The repository uses external Terraform modules in order to configure some components in the cloud. Please find the list of modules below

# Custom-domain TLS via acmebot

By default, the Application Gateway terminates TLS with a self-signed certificate on the auto-generated `*.cloudapp.azure.com` FQDN. To serve a publicly trusted certificate on a custom domain, set `custom_domain` and provide an ACME contact email plus DNS-provider credentials. This deploys the [`shibayan/keyvault-acmebot/azurerm`](https://registry.terraform.io/modules/shibayan/keyvault-acmebot/azurerm) Function App, issues a Let's Encrypt certificate into the existing Key Vault, and (after a follow-up apply) switches the listener to that cert.

The flow runs in two phases because we cannot read a certificate that does not exist yet — the listener cutover has to happen on a second apply, after issuance.

## Phase 1 — deploy acmebot and issue the certificate

```hcl
custom_domain      = "martini.example.com"
acme_contact_email = "ops@example.com"

# Iterate against staging first to avoid Let's Encrypt rate limits:
acme_endpoint = "https://acme-staging-v02.api.letsencrypt.org/directory"

acmebot_dns_provider = {
  cloudflare = {
    api_token = "<scoped Cloudflare token: Zone:Read + DNS:Edit on the zone>"
  }
}
```

`terraform apply`. The acmebot Function App is created, the certificate is issued via DNS-01 (acmebot writes the `_acme-challenge` TXT record at your DNS provider), and the cert lands in the existing Key Vault. The output `next_steps` prints the public IP and follow-up commands.

DNS-01 does **not** depend on the public A record for the domain, so the cert can be issued before the A record exists.

### Other DNS providers

`acmebot_dns_provider` is provider-agnostic — set exactly one of:

```hcl
acmebot_dns_provider = {
  route_53 = { access_key = "...", secret_key = "...", region = "us-east-1" }
}

acmebot_dns_provider = {
  azure_dns = { subscription_id = "<sub-id-of-zone>" }
}

acmebot_dns_provider = {
  google_dns = { key_file64 = "<base64-encoded service-account JSON>" }
}

acmebot_dns_provider = {
  go_daddy = { api_key = "...", api_secret = "..." }
}

acmebot_dns_provider = {
  gandi = { api_key = "..." }
}

acmebot_dns_provider = {
  dns_made_easy = { api_key = "...", secret_key = "..." }
}
```

For Azure DNS the acmebot managed identity needs `DNS Zone Contributor` on the zone — grant it after Phase 1 (`module.acmebot[0].principal_id` is exposed as the `principal_id` output of the module).

## Phase 2 — flip the App Gateway listener

After `next_steps` indicates the cert was issued, add the public DNS A record at your provider:

```
martini.example.com  →  <app_gw_public_ip>
```

Then re-run with the listener flag flipped (and switch to production Let's Encrypt if you used staging in Phase 1):

```hcl
appgw_use_kv_cert = true
acme_endpoint     = "https://acme-v02.api.letsencrypt.org/directory"
```

`terraform apply`. The HTTPS listener is updated to read the certificate from Key Vault via the App Gateway's user-assigned identity. `curl -v https://martini.example.com` should now return Martini with a publicly trusted cert.

## Renewal

acmebot's built-in timer trigger renews the cert ~30 days before expiry. The `null_resource.issue_cert` step is idempotent: it checks the existing cert's expiry on every apply and does nothing if more than 30 days remain. The Application Gateway picks up new versions automatically because it references the cert via `versionless_secret_id`.

## Security note on the acmebot Function App

For simplicity the acmebot Function App is deployed without Easy Auth (`auth_settings = null` inside the module). Its REST endpoints are anonymous — anyone who can reach the Function App URL can issue or revoke certificates. To restrict access, set `acmebot_allowed_ips` to your apply host / CI runner IPs. For production, pair with the upstream module's `auth_settings` input to enable Azure AD Easy Auth.

# Azure SQL Change Event Streaming → Event Hubs

Azure SQL [Change Event Streaming (CES)](https://learn.microsoft.com/en-us/sql/relational-databases/track-changes/change-event-streaming/overview) is a public-preview feature that streams row-level INSERT/UPDATE/DELETE events from an Azure SQL database directly into Azure Event Hubs as CloudEvents. Setting `enable_event_hub = true` provisions the Event Hubs namespace, the hub instances you list, and an `Azure Event Hubs Data Sender` role assignment from the SQL Server's managed identity to each hub. CES itself is configured per-database in T-SQL — Terraform only delivers the destination and the trust relationship.

## Provision the destination

```hcl
enable_sql_server       = true
enable_event_hub        = true
event_hub_namespace_sku = "Standard"
event_hub_capacity      = 1

event_hubs = {
  martini-ces = {
    partition_count   = 4
    message_retention = 1
  }
}
```

`terraform apply`. The `sql_server_principal_id` output is the managed identity that holds `Azure Event Hubs Data Sender` on each hub; the `event_hub_namespace_fqdn` output and the `event-hub-namespace-fqdn` Key Vault secret are what the T-SQL bootstrap below references.

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
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | ~> 4.37.0 |
| <a name="requirement_local"></a> [local](#requirement\_local) | ~> 2.5 |
| <a name="requirement_pkcs12"></a> [pkcs12](#requirement\_pkcs12) | ~> 0.2 |
| <a name="requirement_time"></a> [time](#requirement\_time) | ~> 0.12 |
| <a name="requirement_tls"></a> [tls](#requirement\_tls) | ~> 4.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azuread"></a> [azuread](#provider\_azuread) | 3.8.0 |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | 4.37.0 |
| <a name="provider_local"></a> [local](#provider\_local) | 2.8.0 |
| <a name="provider_null"></a> [null](#provider\_null) | 3.2.4 |
| <a name="provider_pkcs12"></a> [pkcs12](#provider\_pkcs12) | 0.3.2 |
| <a name="provider_random"></a> [random](#provider\_random) | 3.8.1 |
| <a name="provider_time"></a> [time](#provider\_time) | 0.13.1 |
| <a name="provider_tls"></a> [tls](#provider\_tls) | 4.2.1 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_acmebot"></a> [acmebot](#module\_acmebot) | shibayan/keyvault-acmebot/azurerm | ~> 3.1 |
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
| [azurerm_key_vault_access_policy.acmebot](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_access_policy) | resource |
| [azurerm_key_vault_access_policy.appgw_kv](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_access_policy) | resource |
| [azurerm_key_vault_secret.cassandra_admin_password](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_secret) | resource |
| [azurerm_key_vault_secret.cassandra_contact_point](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_secret) | resource |
| [azurerm_key_vault_secret.event_hub_names](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_secret) | resource |
| [azurerm_key_vault_secret.event_hub_namespace_fqdn](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_secret) | resource |
| [azurerm_key_vault_secret.martini_workspace_license](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_secret) | resource |
| [azurerm_key_vault_secret.service_bus_ces_send_connection_string](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_secret) | resource |
| [azurerm_key_vault_secret.service_bus_endpoint](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_secret) | resource |
| [azurerm_key_vault_secret.service_bus_martini_listen_connection_string](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_secret) | resource |
| [azurerm_key_vault_secret.sql_admin_password](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_secret) | resource |
| [azurerm_key_vault_secret.sql_admin_username](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_secret) | resource |
| [azurerm_public_ip.app_gw_pip](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/public_ip) | resource |
| [azurerm_resource_group.rg](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group) | resource |
| [azurerm_role_assignment.cassandra_cosmos_db_subnet_join](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.sql_eventhub_sender](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_servicebus_namespace.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/servicebus_namespace) | resource |
| [azurerm_servicebus_namespace_authorization_rule.ces_send](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/servicebus_namespace_authorization_rule) | resource |
| [azurerm_servicebus_namespace_authorization_rule.martini_listen](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/servicebus_namespace_authorization_rule) | resource |
| [azurerm_servicebus_queue.queues](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/servicebus_queue) | resource |
| [azurerm_servicebus_subscription.martini_subs](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/servicebus_subscription) | resource |
| [azurerm_servicebus_topic.topics](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/servicebus_topic) | resource |
| [azurerm_storage_account.conf](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_account) | resource |
| [azurerm_storage_share.db_pool](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_share) | resource |
| [azurerm_storage_share.designer_workspace_data](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_share) | resource |
| [azurerm_storage_share.designer_workspace_user](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_share) | resource |
| [azurerm_storage_share.runtime_conf_overrides](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_share) | resource |
| [azurerm_storage_share.runtime_lib_ext](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_share) | resource |
| [azurerm_storage_share.runtime_packages](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_share) | resource |
| [azurerm_storage_share_file.designer_version](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_share_file) | resource |
| [azurerm_storage_share_file.tracker_dbxml](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_share_file) | resource |
| [azurerm_user_assigned_identity.appgw_kv](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/user_assigned_identity) | resource |
| [local_file.designer_version](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.tracker_dbxml](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [null_resource.issue_cert](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [pkcs12_from_pem.app_gw](https://registry.terraform.io/providers/chilicat/pkcs12/latest/docs/resources/from_pem) | resource |
| [random_password.admin_password](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [random_password.app_gw_pfx](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [random_password.cassandra_admin](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [random_string.kv_suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [random_string.pip_dns_suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [random_string.storage_suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [time_sleep.wait_for_cluster_settle](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/sleep) | resource |
| [time_sleep.wait_for_eventhub_role_propagation](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/sleep) | resource |
| [time_sleep.wait_for_role_propagation](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/sleep) | resource |
| [tls_private_key.app_gw](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/private_key) | resource |
| [tls_self_signed_cert.app_gw](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/self_signed_cert) | resource |
| [azuread_service_principal.cosmos_db](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/data-sources/service_principal) | data source |
| [azurerm_client_config.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |
| [azurerm_key_vault_certificate.appgw](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/key_vault_certificate) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_aci_docker_image_url"></a> [aci\_docker\_image\_url](#input\_aci\_docker\_image\_url) | Docker image repository for the Martini runtime (without tag). The tag is set via `martini_version`. | `string` | `"lontiplatform/martini-server-runtime"` | no |
| <a name="input_acme_contact_email"></a> [acme\_contact\_email](#input\_acme\_contact\_email) | Contact email registered with the ACME CA (Let's Encrypt). Required when `custom_domain` is set. | `string` | `null` | no |
| <a name="input_acme_endpoint"></a> [acme\_endpoint](#input\_acme\_endpoint) | ACME directory endpoint. Defaults to Let's Encrypt production. Use `https://acme-staging-v02.api.letsencrypt.org/directory` when iterating to avoid hitting rate limits. | `string` | `"https://acme-v02.api.letsencrypt.org/directory"` | no |
| <a name="input_acmebot_allowed_ips"></a> [acmebot\_allowed\_ips](#input\_acmebot\_allowed\_ips) | Optional IP allowlist for the acmebot Function App. When empty, the Function App is reachable from any IP (its endpoints are anonymous — acmebot relies on Easy Auth or this allowlist for access control). Recommended to restrict to the apply host / CI runner range when not using Easy Auth. | `list(string)` | `[]` | no |
| <a name="input_acmebot_dns_provider"></a> [acmebot\_dns\_provider](#input\_acmebot\_dns\_provider) | DNS provider used by acmebot for the ACME DNS-01 challenge. Set exactly one of the optional fields. Required when `custom_domain` is set unless the user is wiring a provider via `acmebot_dns_provider` in another way. | <pre>object({<br/>    cloudflare = optional(object({<br/>      api_token = string<br/>    }))<br/>    route_53 = optional(object({<br/>      access_key = string<br/>      secret_key = string<br/>      region     = string<br/>    }))<br/>    azure_dns = optional(object({<br/>      subscription_id = string<br/>    }))<br/>    google_dns = optional(object({<br/>      key_file64 = string<br/>    }))<br/>    go_daddy = optional(object({<br/>      api_key    = string<br/>      api_secret = string<br/>    }))<br/>    gandi = optional(object({<br/>      api_key = string<br/>    }))<br/>    dns_made_easy = optional(object({<br/>      api_key    = string<br/>      secret_key = string<br/>    }))<br/>  })</pre> | `null` | no |
| <a name="input_appgw_use_kv_cert"></a> [appgw\_use\_kv\_cert](#input\_appgw\_use\_kv\_cert) | When true, the Application Gateway HTTPS listener references the Key-Vault-stored certificate via the AppGW user-assigned identity. Flip to true after the certificate has been issued (typically on a second `terraform apply`). | `bool` | `false` | no |
| <a name="input_cassandra_disk_count"></a> [cassandra\_disk\_count](#input\_cassandra\_disk\_count) | Number of premium managed disks attached to each Cassandra node. Valid only if `enable_cassandra_tracker` is set to `true`. | `number` | `4` | no |
| <a name="input_cassandra_disk_sku"></a> [cassandra\_disk\_sku](#input\_cassandra\_disk\_sku) | Premium disk SKU for each Cassandra node disk (e.g. `P30`, `P40`). Valid only if `enable_cassandra_tracker` is set to `true`. | `string` | `"P30"` | no |
| <a name="input_cassandra_node_count"></a> [cassandra\_node\_count](#input\_cassandra\_node\_count) | Number of Cassandra nodes per data center. Azure Managed Instance for Apache Cassandra requires at least 3. Valid only if `enable_cassandra_tracker` is set to `true`. | `number` | `3` | no |
| <a name="input_cassandra_sku"></a> [cassandra\_sku](#input\_cassandra\_sku) | VM SKU for each Cassandra node. Azure Managed Cassandra only accepts a fixed list of 8-core-and-larger SKUs (see validation). Default `Standard_D8s_v5` is the cheapest supported option for dev/demo; use `Standard_E8s_v5` or larger for production. | `string` | `"Standard_D8s_v5"` | no |
| <a name="input_cassandra_subnet_cidr"></a> [cassandra\_subnet\_cidr](#input\_cassandra\_subnet\_cidr) | CIDR for the delegated subnet hosting Azure Managed Instance for Apache Cassandra. Must be /26 or larger. Valid only if `enable_cassandra_tracker` is set to `true`. | `string` | `"10.0.20.0/26"` | no |
| <a name="input_cassandra_version"></a> [cassandra\_version](#input\_cassandra\_version) | Apache Cassandra major version for the Managed Instance cluster. Valid only if `enable_cassandra_tracker` is set to `true`. | `string` | `"4.0"` | no |
| <a name="input_cpu"></a> [cpu](#input\_cpu) | Number of CPU cores to allocate for the application. | `number` | `2` | no |
| <a name="input_custom_domain"></a> [custom\_domain](#input\_custom\_domain) | Public hostname the Application Gateway should serve (e.g. `martini.example.com`). When set, deploys acmebot and issues a Let's Encrypt certificate into the existing Key Vault. When null, the Application Gateway keeps its self-signed certificate on the `*.cloudapp.azure.com` FQDN. | `string` | `null` | no |
| <a name="input_designer_docker_image_url"></a> [designer\_docker\_image\_url](#input\_designer\_docker\_image\_url) | Docker image repository for the Martini designer (without tag). The tag is set via `martini_version`. Valid only if `enable_designer` is set to `true`. | `string` | `"lontiplatform/martini-designer-online"` | no |
| <a name="input_docker_registry_password"></a> [docker\_registry\_password](#input\_docker\_registry\_password) | Docker Hub access token (preferred) or password paired with `docker_registry_username`. | `string` | `""` | no |
| <a name="input_docker_registry_username"></a> [docker\_registry\_username](#input\_docker\_registry\_username) | Docker Hub username used to authenticate image pulls and avoid anonymous rate limits. Leave empty to pull anonymously. | `string` | `""` | no |
| <a name="input_enable_cassandra_tracker"></a> [enable\_cassandra\_tracker](#input\_enable\_cassandra\_tracker) | Should Martini use Azure Managed Instance for Apache Cassandra as the tracker backend? | `bool` | `false` | no |
| <a name="input_enable_designer"></a> [enable\_designer](#input\_enable\_designer) | Deploy `lontiplatform/martini-designer-online` as a single-instance ACI instead of the runtime. Mutually exclusive with the runtime deployment. | `bool` | `false` | no |
| <a name="input_enable_event_hub"></a> [enable\_event\_hub](#input\_enable\_event\_hub) | Should an Azure Event Hubs namespace be provisioned as the destination for Azure SQL Change Event Streaming (CES)? Pair with `enable_sql_server = true` so the SQL Server's managed identity can be granted `Azure Event Hubs Data Sender` on the hub instances. | `bool` | `false` | no |
| <a name="input_enable_service_bus"></a> [enable\_service\_bus](#input\_enable\_service\_bus) | Should an Azure Service Bus namespace be provisioned for inbound messaging (e.g. Azure SQL CES -> Martini)? | `bool` | `false` | no |
| <a name="input_enable_sql_server"></a> [enable\_sql\_server](#input\_enable\_sql\_server) | Should Martini use SQL Server database? | `bool` | `false` | no |
| <a name="input_event_hub_capacity"></a> [event\_hub\_capacity](#input\_event\_hub\_capacity) | Throughput units (Standard) or processing units (Premium) for the namespace. Ignored for Basic. Valid only if `enable_event_hub` is set to `true`. | `number` | `1` | no |
| <a name="input_event_hub_namespace_sku"></a> [event\_hub\_namespace\_sku](#input\_event\_hub\_namespace\_sku) | SKU tier for the Event Hubs namespace. Valid only if `enable_event_hub` is set to `true`. | `string` | `"Standard"` | no |
| <a name="input_event_hubs"></a> [event\_hubs](#input\_event\_hubs) | Event Hub instances to create on the namespace, keyed by name. Each entry sets `partition_count` and `message_retention` (days). The SQL Server managed identity is granted `Azure Event Hubs Data Sender` on each hub. Valid only if `enable_event_hub` is set to `true`. | <pre>map(object({<br/>    partition_count   = number<br/>    message_retention = number<br/>  }))</pre> | `{}` | no |
| <a name="input_martini_home_path"></a> [martini\_home\_path](#input\_martini\_home\_path) | Path to the Martini workspace inside the container image. Default matches the official lontiplatform/martini-server-runtime image. | `string` | `"/data"` | no |
| <a name="input_martini_version"></a> [martini\_version](#input\_martini\_version) | Tag of the Martini Docker image to deploy. Applied to the runtime image or the designer image depending on `enable_designer`. | `string` | `"2.7.2"` | no |
| <a name="input_martini_workspace_license"></a> [martini\_workspace\_license](#input\_martini\_workspace\_license) | Full license text to be used with Martini | `string` | n/a | yes |
| <a name="input_max_size_gb"></a> [max\_size\_gb](#input\_max\_size\_gb) | The max size of the database in gigabytes. | `number` | `50` | no |
| <a name="input_memory"></a> [memory](#input\_memory) | Amount of memory (in GB) to allocate for the application | `number` | `4` | no |
| <a name="input_name_suffix"></a> [name\_suffix](#input\_name\_suffix) | Suffix to add to the resources' names | `string` | `""` | no |
| <a name="input_node_count"></a> [node\_count](#input\_node\_count) | Number of Martini container instances to run behind the Application Gateway | `number` | `1` | no |
| <a name="input_private_subnet_cidrs"></a> [private\_subnet\_cidrs](#input\_private\_subnet\_cidrs) | A list of prefixes for public subnets. | `list(string)` | <pre>[<br/>  "10.0.11.0/24",<br/>  "10.0.12.0/24"<br/>]</pre> | no |
| <a name="input_public_subnet_cidrs"></a> [public\_subnet\_cidrs](#input\_public\_subnet\_cidrs) | A list of prefixes for public subnets. | `list(string)` | <pre>[<br/>  "10.0.1.0/24",<br/>  "10.0.2.0/24"<br/>]</pre> | no |
| <a name="input_rg_location"></a> [rg\_location](#input\_rg\_location) | Azure region to deploy resources into | `string` | n/a | yes |
| <a name="input_service_bus_capacity"></a> [service\_bus\_capacity](#input\_service\_bus\_capacity) | Messaging units for the Premium SKU. Ignored for Basic/Standard. Valid only if `enable_service_bus` is set to `true`. | `number` | `1` | no |
| <a name="input_service_bus_premium_messaging_partitions"></a> [service\_bus\_premium\_messaging\_partitions](#input\_service\_bus\_premium\_messaging\_partitions) | Messaging partitions for the Premium SKU. Ignored for Basic/Standard. Valid only if `enable_service_bus` is set to `true`. | `number` | `1` | no |
| <a name="input_service_bus_queues"></a> [service\_bus\_queues](#input\_service\_bus\_queues) | Queue names to create on the namespace. Valid only if `enable_service_bus` is set to `true`. | `list(string)` | `[]` | no |
| <a name="input_service_bus_sku"></a> [service\_bus\_sku](#input\_service\_bus\_sku) | SKU tier for the Service Bus namespace. Basic does not support topics. Valid only if `enable_service_bus` is set to `true`. | `string` | `"Standard"` | no |
| <a name="input_service_bus_topics"></a> [service\_bus\_topics](#input\_service\_bus\_topics) | Topic names to create on the namespace. Each topic gets a single subscription named `martini`. Requires `service_bus_sku` of `Standard` or `Premium`. Valid only if `enable_service_bus` is set to `true`. | `list(string)` | `[]` | no |
| <a name="input_sql_database_name"></a> [sql\_database\_name](#input\_sql\_database\_name) | Name of the SQL database. Valid only if `enable_sql_server` is set to `true` | `string` | `"martini"` | no |
| <a name="input_sql_server_admin_username"></a> [sql\_server\_admin\_username](#input\_sql\_server\_admin\_username) | Username to set in the SQl Server. Valid only if `enable_sql_server` is set to `true` | `string` | `null` | no |
| <a name="input_sql_server_version"></a> [sql\_server\_version](#input\_sql\_server\_version) | The RDS engine version to use. Valid only if `enable_sql_server` is set to `true` | `string` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Common tags for components created in the infrastructure | `map(string)` | <pre>{<br/>  "Application": "Martini",<br/>  "Repository": "https://github.com/lontiplatform/martini-azure-terraform-template"<br/>}</pre> | no |
| <a name="input_vnet_address_space"></a> [vnet\_address\_space](#input\_vnet\_address\_space) | Virtual Network CIDR | `list(string)` | <pre>[<br/>  "10.0.0.0/18"<br/>]</pre> | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_app_gw_public_ip"></a> [app\_gw\_public\_ip](#output\_app\_gw\_public\_ip) | Public IP of the Application Gateway. Point your custom-domain A record at this address. |
| <a name="output_app_gw_url"></a> [app\_gw\_url](#output\_app\_gw\_url) | n/a |
| <a name="output_cassandra_cluster_name"></a> [cassandra\_cluster\_name](#output\_cassandra\_cluster\_name) | n/a |
| <a name="output_cassandra_contact_point"></a> [cassandra\_contact\_point](#output\_cassandra\_contact\_point) | n/a |
| <a name="output_cassandra_port"></a> [cassandra\_port](#output\_cassandra\_port) | n/a |
| <a name="output_event_hub_names"></a> [event\_hub\_names](#output\_event\_hub\_names) | n/a |
| <a name="output_event_hub_namespace_fqdn"></a> [event\_hub\_namespace\_fqdn](#output\_event\_hub\_namespace\_fqdn) | n/a |
| <a name="output_event_hub_namespace_name"></a> [event\_hub\_namespace\_name](#output\_event\_hub\_namespace\_name) | n/a |
| <a name="output_next_steps"></a> [next\_steps](#output\_next\_steps) | Follow-up actions when a custom domain is configured but the listener has not yet been switched to the Key Vault cert. |
| <a name="output_resource_group_location"></a> [resource\_group\_location](#output\_resource\_group\_location) | n/a |
| <a name="output_resource_group_name"></a> [resource\_group\_name](#output\_resource\_group\_name) | n/a |
| <a name="output_service_bus_endpoint"></a> [service\_bus\_endpoint](#output\_service\_bus\_endpoint) | n/a |
| <a name="output_service_bus_namespace_name"></a> [service\_bus\_namespace\_name](#output\_service\_bus\_namespace\_name) | n/a |
| <a name="output_service_bus_queue_names"></a> [service\_bus\_queue\_names](#output\_service\_bus\_queue\_names) | n/a |
| <a name="output_service_bus_topic_names"></a> [service\_bus\_topic\_names](#output\_service\_bus\_topic\_names) | n/a |
| <a name="output_sql_server_principal_id"></a> [sql\_server\_principal\_id](#output\_sql\_server\_principal\_id) | Principal ID of the SQL Server managed identity. Verify in the portal that this principal holds `Azure Event Hubs Data Sender` on each event hub before running the CES bootstrap T-SQL. |
| <a name="output_subnet_prefixes"></a> [subnet\_prefixes](#output\_subnet\_prefixes) | n/a |
<!-- END_TF_DOCS -->