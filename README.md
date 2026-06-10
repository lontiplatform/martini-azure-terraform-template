# Martini Terraform Template

The repository contains a Terraform template to create a complete infrastructure running Martini Runtime in the cloud 
on Azure Container Apps along with optional dependency such as an SQL database.

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
| [NAT Gateway](https://azure.microsoft.com/en-us/pricing/details/azure-nat-gateway/) | Standard | $0.045/h resource + $0.045/GB data processed | **~$32.85** (+ data) |
| [Container Apps](https://azure.microsoft.com/en-us/pricing/details/container-apps/) — 1× Martini runtime | Consumption, 2 vCPU + 4 GB, 1 replica always active | per-second vCPU/memory billing (free monthly grant applies) | **~$72** (1 always-active replica) |
| [Key Vault](https://azure.microsoft.com/en-us/pricing/details/key-vault/) | Standard | $0.03 per 10K operations | **< $1** (ops-only) |
| [Storage Account — Files](https://azure.microsoft.com/en-us/pricing/details/storage/files/) | Standard LRS, transaction-optimized | $0.06/GB-month for used data + per-op | **~$1–3** (low usage) |
| Virtual Network | n/a | free | $0 |
| **Baseline total** | | | **≈ $108 / month** |

> The Container App environment uses **external** ingress with its built-in load balancer and a free Microsoft-managed certificate on the `*.azurecontainerapps.io` FQDN — there is no Application Gateway, public IP, or self-managed cert pipeline in the baseline.

## Optional flag deltas

Each row is **on top of** the baseline. Combine them for your configuration.

| Flag | What it adds | Est. delta (USD/month) |
|---|---|---|
| `enable_designer = true` | Swaps the runtime container app for a single Designer container app at the same `martini_cpu` / `martini_memory`; provisions larger storage shares (billed by actual usage, not quota). | **~$0** (no extra compute; storage delta negligible at low usage) |
| `enable_sql_server = true` | [Azure SQL Database Single, Standard S0](https://azure.microsoft.com/en-us/pricing/details/azure-sql-database/single/) (10 DTU) @ $0.4839/day — includes up to 250 GB storage. | **+~$14.71** |
| `enable_cassandra_tracker = true` | [Azure Managed Instance for Apache Cassandra](https://azure.microsoft.com/en-us/pricing/details/managed-instance-apache-cassandra/): 3× `Standard_D8s_v5` nodes @ $0.48/h + 3× [P30 premium disks](https://azure.microsoft.com/en-us/pricing/details/managed-disks/) @ $135.17/mo + Cassandra backup @ $0.10/GB-mo. | **+~$1,457** |
| `enable_event_hub = true` | [Event Hubs](https://azure.microsoft.com/en-us/pricing/details/event-hubs/) Basic namespace + 1 throughput unit @ $0.015/h, plus $0.028 per 1 M ingress events. | **+~$11** (+ event volume) |
| `enable_communication_services_email = true` (default) | [Azure Communication Services Email](https://azure.microsoft.com/en-us/pricing/details/communication-services/) — no fixed monthly fee, billed per message. List price as of 2026-05-12: $0.00025 per email + $0.00012/MB of message data. Azure-managed-domain quota caps usage at ~100/day. | **~$0** at quota (≤ ~$0.75/mo) |
| `custom_domain = "<fqdn>"` | Binds a custom domain to the Container App's external ingress with a free [ACA managed certificate](https://learn.microsoft.com/en-us/azure/container-apps/custom-domains-managed-certificates) (DigiCert-issued, ~6-month, auto-renewing). No extra Azure resources. | **$0** (managed cert is free) |
| `existing_vnet = { ... }` (Mode B) | Skips the NAT Gateway owned by this template — outbound NAT becomes your VNet's responsibility. | **−~$32.85** (saves NAT Gateway) |

## Scaling levers

How the numeric inputs in `variables.tf` move the cost lines above:

- **`martini_node_count = N`** (runtime mode only) — sets both `min_replicas` and `max_replicas` on the runtime [Container App](https://azure.microsoft.com/en-us/pricing/details/container-apps/), so `N` replicas stay always-active. At defaults that's ≈ **+$72/month per extra replica**.
- **`martini_cpu` / `martini_memory`** — Container Apps Consumption bills per active vCPU-second and GB-second (with a free monthly grant). Cost scales linearly with both values per always-active replica.
- **`cassandra_sku`** — list ranges from `Standard_D8s_v5` (**$0.48/h/node**, the default and cheapest accepted SKU) to `Standard_E32s_v5` (**$2.52/h/node**); picking a larger SKU can multiply the Cassandra compute line by up to ~5×.
- **`cassandra_node_count`** — linear multiplier; minimum 3.
- **`cassandra_disk_count` / `cassandra_disk_sku`** — each [P30 disk](https://azure.microsoft.com/en-us/pricing/details/managed-disks/) is $135.17/mo; bumping to P40 ($270.34/mo) or adding disks per node multiplies the disk line accordingly.
- **`event_hub_namespace_sku`** — Basic → Standard moves the throughput-unit price from **$0.015/h** to **$0.03/h** and unlocks features billed separately (Capture $0.10/h, Kafka endpoint $0.09/h).
- **`event_hub_capacity`** — linear multiplier on the throughput-unit line.
- **`sql_max_size_gb`** — S0 already includes 250 GB; raising this stays free up to that ceiling. Going past 250 GB requires a higher SQL SKU than S0.

# Bring-your-own VNet (Mode B)

By default the template provisions a fresh VNet plus a NAT gateway. To deploy into an existing corporate VNet instead, set `existing_vnet` and supply CIDRs for the workload subnets (`aci`, `aca`, and — if `enable_cassandra_tracker = true` — `cassandra`):

```hcl
existing_vnet = {
  name                = "vnet-DevCentralUS"
  resource_group_name = "network"
}

aci_subnet_cidr       = "172.16.3.16/28"
aca_subnet_cidr       = "172.16.3.64/27"  # /27 minimum for a Container Apps workload-profile environment
cassandra_subnet_cidr = "172.16.3.192/26" # /26 minimum for Managed Cassandra

# Optional: associate the new ACI / Cassandra subnets with the network team's
# shared route table and NSG.
byo_vnet_route_table_id  = "/subscriptions/.../routeTables/Route-Dev-Prd"
byo_vnet_workload_nsg_id = "/subscriptions/.../networkSecurityGroups/nsg-cus-dev-network"
```

In Mode B the template:

- creates `azurerm_subnet.aci` (delegated to `Microsoft.ContainerInstance/containerGroups`), `azurerm_subnet.aca` (delegated to `Microsoft.App/environments`), and `azurerm_subnet.cassandra` (delegated to `Microsoft.DocumentDB/cassandraClusters`) inside `existing_vnet.name`
- does **not** create a NAT gateway — outbound NAT is your VNet's responsibility

The Terraform principal must hold `Microsoft.Network/virtualNetworks/subnets/write` on the existing VNet. Two caveats worth checking with whoever owns that VNet:

- their VNet's Terraform must not declare inline `subnet { ... }` blocks on `azurerm_virtual_network` (this would delete our subnets on their next apply); they should manage subnets via standalone `azurerm_subnet` resources or `lifecycle { ignore_changes = [subnet] }`.
- the Container Apps environment is reached over the public internet via its external ingress, so the `aca` subnet only needs outbound access for the workload. Leaving `byo_vnet_workload_nsg_id = null` keeps the subnets on Azure's default rules, which already cover this.

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

- **Standard SKU or higher is required.** Martini's CES consumer connects via the Kafka protocol on port 9093 (SASL_SSL). Basic-tier namespaces do not expose a Kafka endpoint — the TCP listener doesn't exist and Kafka clients see dropped connections. `event_hub_namespace_sku` defaults to `Standard` for this reason; only override down to `Basic` if you have a non-Kafka consumer in mind.
- The namespace is provisioned with `local_authentication_enabled = true` and ships a namespace-level listen-only SAS rule (`martini-listener`). The consumers (Designer + Runtime) authenticate via SASL/PLAIN using `MR_EVENT_HUB_CONNECTION_STRING`, sourced from the `event-hub-listener-connection-string` Key Vault secret. This is the active auth path because Martini Designer's embedded Kafka client can't currently complete SASL/OAUTHBEARER against AAD.
- Each container group still runs with a system-assigned managed identity, and each MI is still granted `Azure Event Hubs Data Receiver` on every hub in `event_hubs` — dormant until Martini's Kafka client can complete OAUTHBEARER, at which point dropping the connection-string env var falls back to AAD without further infra changes. In runtime mode with `martini_node_count = N`, this is `N × len(event_hubs)` assignments — one per (replica, hub) pair so each replica's identity can read independently.
- All consumers read from the implicit `$Default` consumer group. The runtime fan-out works on `$Default` too — Event Hubs load-balances partitions across all consumers in the group regardless of name.
- The container receives three plaintext env vars so it can connect without manual config: `MR_EVENT_HUB_NAMESPACE_FQDN`, `MR_EVENT_HUB_NAMES` (comma-separated), and `MR_EVENT_HUB_CONSUMER_GROUP` (always `$Default`); plus `MR_EVENT_HUB_CONNECTION_STRING` as a secure env var.
- A 5-minute `time_sleep` after the role assignments lets RBAC propagate before the container's first connect — not load-bearing for the SAS path, but kept in place so re-enabling OAUTHBEARER doesn't reintroduce the 1–2 minute propagation race.

# Outbound email via Azure Communication Services (SMTP relay)

Azure Communication Services (ACS) Email is the first-party equivalent of AWS SES. With `enable_communication_services_email = true` (the default) the template provisions an Email Communication Service backed by an Azure-managed sender subdomain (`<random>.azurecomm.net`) plus a Communication Services resource exposing the SMTP relay at `smtp.azurecomm.net:587` (STARTTLS, SASL LOGIN). Martini packages can send mail through it without any SDK changes — only standard SMTP client config.

## Prerequisite: Entra application for SMTP authentication

ACS SMTP authentication requires a Microsoft Entra application; this template **does not create it** because most Terraform principals lack `Application.ReadWrite.*` on the directory. Have your tenant admin pre-create the app — the `Application Developer` directory role is enough — then pass its identifiers in via `communication_email_smtp_entra_app`:

```hcl
communication_email_smtp_entra_app = {
  client_id     = "<Application (client) ID from the App Registration blade>"
  sp_object_id  = "<Object ID from Enterprise Applications → this app (NOT the App Registration Object ID)>"
  client_secret = "<value of a client secret created on the app>"
}
```

The app must live in the same tenant as the subscription. The template assigns the built-in `Communication and Email Service Owner` role to the app's service principal on the Communication Services resource and creates an `Microsoft.Communication/communicationServices/smtpUsernames` child resource that maps an SMTP login string to the app — both are required for ACS SMTP AUTH to succeed.

## What gets provisioned

- `azurerm_resource_provider_registration` — registers `Microsoft.Communication` on the subscription (one-time bootstrap)
- `azurerm_email_communication_service` — the Email Communication Service parent
- `azurerm_email_communication_service_domain` — Azure-managed sender domain
- `azurerm_email_communication_service_domain_sender_username` — sender username (default `martini` → `martini@<random>.azurecomm.net`)
- `azurerm_communication_service` — the Communication Services resource, with the email domain linked via `azurerm_communication_service_email_domain_association`
- `azurerm_role_assignment` — built-in `Communication and Email Service Owner` role on the Communication Services resource for the BYO service principal (the role required for SMTP send)
- `azapi_resource` — `Microsoft.Communication/communicationServices/smtpUsernames` child resource mapping the SMTP login string (defaults to `martini`) to the BYO Entra application

The `data_location` (ACS data-residency label) is derived from `rg_location` via a built-in map (e.g., `westeurope` → `"Europe"`, `eastus` → `"United States"`). Unmapped regions silently fall back to `"United States"`.

Destroying this stack also unregisters `Microsoft.Communication` from the subscription, which can break unrelated ACS resources in the same subscription. If you share the subscription with other ACS workloads, pre-register the namespace manually (`az provider register --namespace Microsoft.Communication`) and leave the registration in place across destroys.

## How Martini sees it

The runtime and designer container groups receive five environment variables when this feature is enabled — three plaintext, two secure:

| Var | Source | Notes |
|---|---|---|
| `MR_SMTP_HOST` | `"smtp.azurecomm.net"` | plain |
| `MR_SMTP_PORT` | `"587"` | plain |
| `MR_SMTP_SENDER` | `<sender_username>@<azure-managed-domain>` | plain |
| `MR_SMTP_USERNAME` | the literal SMTP Username string registered on the ACS resource (defaults to `communication_email_sender_username`, i.e. `martini`) | secure |
| `MR_SMTP_PASSWORD` | Entra app client secret | secure |

The same values are also written to Key Vault as the `smtp-host`, `smtp-port`, `smtp-username`, `smtp-password`, and `smtp-sender-address` secrets for out-of-band consumers (CI, ops scripts).

## Quotas and caveats

- **Azure-managed-domain limit: ~100 emails/day, 10 recipients per message.** This is fine for alerts and operational notifications but **not** suitable for user-facing transactional volume. For production volume you need a custom verified domain (SPF/DKIM/DMARC); that is **not** automated by this template — bring your own domain into the Email Communication Service via the Azure portal once you outgrow the managed domain.
- **Deliverability is low** on the managed subdomain. Test inboxes will often classify mail as spam until you switch to a custom domain.
- **Outbound port 25 is blocked from Azure compute.** Always use port 587 with STARTTLS — port 25 will not work even with the ACS endpoint.
- **Role propagation:** a 60-second `time_sleep` after the role assignment gates container creation; bump it if you see `AuthorizationFailed` on Martini's first send.
- **Password rotation:** the BYO Entra app client secret is opaque to Terraform; rotate it out-of-band (Azure portal or Microsoft Graph) and feed the new value back through the `communication_email_smtp_entra_app.client_secret` variable. The container groups consume the secret as a `secure_environment_variable`, so they will be re-created on the next apply that detects the change.

## Disabling

Set `enable_communication_services_email = false` to skip the entire stack (no Entra app, no Communication Services resource, no Key Vault secrets, no env vars). Defaults to `true` because most Martini deployments want outbound mail and the cost at quota is effectively $0.

# Custom domain TLS via ACA managed certificates

Setting `custom_domain = "<fqdn>"` (e.g. `cooper.external.lonti.com`) binds the FQDN to the Container App's external ingress and issues a **free [Azure-managed certificate](https://learn.microsoft.com/en-us/azure/container-apps/custom-domains-managed-certificates)** (DigiCert-issued, ~6-month validity, auto-renewing). There is no Application Gateway, Key Vault cert, Acmebot Function App, or helper script — Azure manages the certificate lifecycle. Leaving `custom_domain = ""` (the default) leaves the app reachable on its free `*.azurecontainerapps.io` FQDN with Microsoft's auto-managed cert.

## Why this is a two-phase apply

A managed certificate can only be issued after DigiCert validates domain ownership by reaching the app over public DNS, and the DNS records can only be created once the app exists and exposes its verification id — a [chicken-and-egg the azurerm provider does not resolve in one pass](https://github.com/hashicorp/terraform-provider-azurerm/issues/21866). The template handles this with the `custom_domain_dns_ready` gate:

**Phase 1 — create the app, read the required DNS records.** With `custom_domain` set and `custom_domain_dns_ready = false` (default), apply. The Container App comes up on its `*.azurecontainerapps.io` FQDN, and the `custom_domain_dns_records` output lists exactly what to create:

```
terraform output custom_domain_dns_records
```

```hcl
[
  { name = "cooper.external.lonti.com",       type = "CNAME", value = "cooper-runtime.bluefield-1234.eastus.azurecontainerapps.io" },
  { name = "asuid.cooper.external.lonti.com", type = "TXT",   value = "ABCD...1234" },
]
```

**Phase 1.5 — create those two records** in whatever zone owns `<custom_domain>`.

**Phase 2 — issue and bind the cert.** Set `custom_domain_dns_ready = true` and apply again. This creates `azurerm_container_app_environment_managed_certificate` (validated via the CNAME) and binds it to the domain with `SniEnabled` via `azurerm_container_app_custom_domain`. Once issued, Azure auto-renews the cert before expiry — no further Terraform action is needed.

## Limitations vs the previous Acmebot pipeline

- **Single hostname only.** ACA managed certificates do not support wildcard (`*.example.com`) or multi-SAN certs. Each `custom_domain` binds exactly one FQDN. (The Acmebot/Let's Encrypt path this replaced could do wildcards via DNS-01; if you ever need that, you must reintroduce a self-managed cert pipeline.)
- **App must be publicly reachable.** DigiCert validates by reaching the public FQDN, so managed certs are incompatible with internal-only environments or apps fronted by a gateway. This template's environment is external by design (`internal_load_balancer_enabled = false`).
- **No static inbound IP.** Clients resolve the ACA ingress FQDN (a shared, non-contractually-stable IP). If a consumer needs to allowlist a fixed ingress IP, this template no longer provides one.

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
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 5.0 |
| <a name="requirement_azapi"></a> [azapi](#requirement\_azapi) | ~> 2.0 |
| <a name="requirement_azuread"></a> [azuread](#requirement\_azuread) | ~> 3.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | ~> 4.38 |
| <a name="requirement_local"></a> [local](#requirement\_local) | ~> 2.5 |
| <a name="requirement_time"></a> [time](#requirement\_time) | ~> 0.12 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 5.100.0 |
| <a name="provider_azapi"></a> [azapi](#provider\_azapi) | 2.9.0 |
| <a name="provider_azuread"></a> [azuread](#provider\_azuread) | 3.8.0 |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | 4.73.0 |
| <a name="provider_local"></a> [local](#provider\_local) | 2.9.0 |
| <a name="provider_random"></a> [random](#provider\_random) | 3.9.0 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |
| <a name="provider_time"></a> [time](#provider\_time) | 0.14.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_nat_gw"></a> [nat\_gw](#module\_nat\_gw) | Azure/avm-res-network-natgateway/azurerm | ~> 0.2.1 |
| <a name="module_sql_server"></a> [sql\_server](#module\_sql\_server) | Azure/avm-res-sql-server/azurerm | ~> 0.1.5 |
| <a name="module_virtual_network"></a> [virtual\_network](#module\_virtual\_network) | Azure/avm-res-network-virtualnetwork/azurerm | ~> 0.9.3 |

## Resources

| Name | Type |
|------|------|
| [azapi_resource.acs_smtp_username](https://registry.terraform.io/providers/azure/azapi/latest/docs/resources/resource) | resource |
| [azurerm_communication_service.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/communication_service) | resource |
| [azurerm_communication_service_email_domain_association.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/communication_service_email_domain_association) | resource |
| [azurerm_container_app.martini](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/container_app) | resource |
| [azurerm_container_app.martini_designer](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/container_app) | resource |
| [azurerm_container_app_custom_domain.martini](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/container_app_custom_domain) | resource |
| [azurerm_container_app_custom_domain.martini_designer](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/container_app_custom_domain) | resource |
| [azurerm_container_app_environment.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/container_app_environment) | resource |
| [azurerm_container_app_environment_managed_certificate.custom](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/container_app_environment_managed_certificate) | resource |
| [azurerm_container_app_environment_storage.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/container_app_environment_storage) | resource |
| [azurerm_container_registry.ecr_mirror](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/container_registry) | resource |
| [azurerm_container_registry_scope_map.designer_pull](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/container_registry_scope_map) | resource |
| [azurerm_container_registry_token.aci_designer_pull](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/container_registry_token) | resource |
| [azurerm_container_registry_token_password.aci_designer_pull](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/container_registry_token_password) | resource |
| [azurerm_cosmosdb_cassandra_cluster.tracker](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/cosmosdb_cassandra_cluster) | resource |
| [azurerm_cosmosdb_cassandra_datacenter.tracker](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/cosmosdb_cassandra_datacenter) | resource |
| [azurerm_email_communication_service.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/email_communication_service) | resource |
| [azurerm_email_communication_service_domain.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/email_communication_service_domain) | resource |
| [azurerm_email_communication_service_domain_sender_username.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/email_communication_service_domain_sender_username) | resource |
| [azurerm_eventhub.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/eventhub) | resource |
| [azurerm_eventhub_namespace.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/eventhub_namespace) | resource |
| [azurerm_eventhub_namespace_authorization_rule.martini_listener](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/eventhub_namespace_authorization_rule) | resource |
| [azurerm_key_vault.key_vault](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault) | resource |
| [azurerm_key_vault_access_policy.deployer](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_access_policy) | resource |
| [azurerm_key_vault_secret.cassandra_admin_password](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_secret) | resource |
| [azurerm_key_vault_secret.cassandra_contact_point](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_secret) | resource |
| [azurerm_key_vault_secret.event_hub_listener_connection_string](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_secret) | resource |
| [azurerm_key_vault_secret.event_hub_names](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_secret) | resource |
| [azurerm_key_vault_secret.event_hub_namespace_fqdn](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_secret) | resource |
| [azurerm_key_vault_secret.martini_workspace_license](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_secret) | resource |
| [azurerm_key_vault_secret.smtp_host](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_secret) | resource |
| [azurerm_key_vault_secret.smtp_password](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_secret) | resource |
| [azurerm_key_vault_secret.smtp_port](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_secret) | resource |
| [azurerm_key_vault_secret.smtp_sender_address](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_secret) | resource |
| [azurerm_key_vault_secret.smtp_username](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_secret) | resource |
| [azurerm_key_vault_secret.sql_admin_password](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_secret) | resource |
| [azurerm_key_vault_secret.sql_admin_username](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_secret) | resource |
| [azurerm_log_analytics_workspace.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/log_analytics_workspace) | resource |
| [azurerm_monitor_action_group.ops](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_action_group) | resource |
| [azurerm_monitor_activity_log_alert.aca_terminations](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_activity_log_alert) | resource |
| [azurerm_monitor_diagnostic_setting.conf_file](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_diagnostic_setting) | resource |
| [azurerm_monitor_metric_alert.aca_memory_high](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_metric_alert) | resource |
| [azurerm_monitor_metric_alert.storage_availability](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_metric_alert) | resource |
| [azurerm_monitor_metric_alert.storage_e2e_latency](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_metric_alert) | resource |
| [azurerm_monitor_scheduled_query_rules_alert_v2.storage_throttling](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_scheduled_query_rules_alert_v2) | resource |
| [azurerm_mssql_firewall_rule.martini_egress](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/mssql_firewall_rule) | resource |
| [azurerm_nat_gateway.aca](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/nat_gateway) | resource |
| [azurerm_nat_gateway_public_ip_association.aca](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/nat_gateway_public_ip_association) | resource |
| [azurerm_public_ip.aca_nat](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/public_ip) | resource |
| [azurerm_resource_group.rg](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group) | resource |
| [azurerm_resource_provider_registration.communication](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_provider_registration) | resource |
| [azurerm_role_assignment.acs_smtp_email_owner](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.cassandra_cosmos_db_subnet_join](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.ces_azure_sql_to_eh](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.martini_designer_eh_receiver](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.martini_runtime_eh_receiver](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_route_table.aca](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/route_table) | resource |
| [azurerm_storage_account.conf](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_account) | resource |
| [azurerm_storage_share.db_pool](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_share) | resource |
| [azurerm_storage_share.designer_workspace_data](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_share) | resource |
| [azurerm_storage_share.designer_workspace_user](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_share) | resource |
| [azurerm_storage_share.runtime_conf_overrides](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_share) | resource |
| [azurerm_storage_share.runtime_lib_ext](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_share) | resource |
| [azurerm_storage_share.runtime_packages](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_share) | resource |
| [azurerm_storage_share_directory.designer_runtime_conf](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_share_directory) | resource |
| [azurerm_storage_share_directory.designer_runtime_db_pool](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_share_directory) | resource |
| [azurerm_storage_share_file.designer_sqlserver_dbxml](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_share_file) | resource |
| [azurerm_storage_share_file.designer_tracker_dbxml](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_share_file) | resource |
| [azurerm_storage_share_file.designer_version](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_share_file) | resource |
| [azurerm_storage_share_file.sqlserver_dbxml](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_share_file) | resource |
| [azurerm_storage_share_file.tracker_dbxml](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_share_file) | resource |
| [azurerm_subnet.aca](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet) | resource |
| [azurerm_subnet.aci](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet) | resource |
| [azurerm_subnet.cassandra](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet) | resource |
| [azurerm_subnet_nat_gateway_association.aca](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet_nat_gateway_association) | resource |
| [azurerm_subnet_network_security_group_association.aca](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet_network_security_group_association) | resource |
| [azurerm_subnet_network_security_group_association.aci](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet_network_security_group_association) | resource |
| [azurerm_subnet_network_security_group_association.cassandra](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet_network_security_group_association) | resource |
| [azurerm_subnet_route_table_association.aca](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet_route_table_association) | resource |
| [azurerm_subnet_route_table_association.aci](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet_route_table_association) | resource |
| [azurerm_subnet_route_table_association.cassandra](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet_route_table_association) | resource |
| [local_file.designer_version](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.sqlserver_dbxml](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.tracker_dbxml](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [random_password.admin_password](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [random_password.cassandra_admin](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [random_string.ecr_acr_suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [random_string.kv_suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [random_string.storage_suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [terraform_data.bind_custom_domain](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.ecr_image_import](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [time_sleep.acs_smtp_role_propagation](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/sleep) | resource |
| [time_sleep.ces_role_propagation](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/sleep) | resource |
| [time_sleep.martini_eh_role_propagation](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/sleep) | resource |
| [time_sleep.wait_for_cluster_settle](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/sleep) | resource |
| [time_sleep.wait_for_role_propagation](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/sleep) | resource |
| [aws_ecr_authorization_token.designer](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ecr_authorization_token) | data source |
| [azuread_service_principal.cosmos_db](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/data-sources/service_principal) | data source |
| [azurerm_client_config.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |
| [azurerm_mssql_server.ces_source](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/mssql_server) | data source |
| [azurerm_public_ip.nat_gw](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/public_ip) | data source |
| [azurerm_virtual_network.existing](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/virtual_network) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_aca_subnet_cidr"></a> [aca\_subnet\_cidr](#input\_aca\_subnet\_cidr) | CIDR for the Azure Container Apps delegated subnet. Minimum /27 (32 IPs) for a Workload Profile environment. Required when existing\_vnet is set; in Mode A the subnet is created from this CIDR via the AVM module. | `string` | `null` | no |
| <a name="input_aci_subnet_cidr"></a> [aci\_subnet\_cidr](#input\_aci\_subnet\_cidr) | CIDR for the ACI delegated subnet inside the existing VNet. Required when existing\_vnet is set; ignored otherwise. | `string` | `null` | no |
| <a name="input_alert_emails"></a> [alert\_emails](#input\_alert\_emails) | List of email addresses that receive every alert fired by the action group. Each address becomes a separate email\_receiver. Leave empty to provision the action group with no receivers (alerts still fire but go nowhere). | `list(string)` | `[]` | no |
| <a name="input_byo_vnet_route_table_id"></a> [byo\_vnet\_route\_table\_id](#input\_byo\_vnet\_route\_table\_id) | Optional ID of a pre-existing route table to associate with the ACI and Cassandra subnets when existing\_vnet is set. Leave null to use Azure system routes. Ignored when existing\_vnet is null. | `string` | `null` | no |
| <a name="input_byo_vnet_workload_nsg_id"></a> [byo\_vnet\_workload\_nsg\_id](#input\_byo\_vnet\_workload\_nsg\_id) | Optional ID of a pre-existing NSG to associate with the ACI and Cassandra subnets when existing\_vnet is set. Ignored when existing\_vnet is null. | `string` | `null` | no |
| <a name="input_cassandra_disk_count"></a> [cassandra\_disk\_count](#input\_cassandra\_disk\_count) | Number of premium managed disks attached to each Cassandra node. Valid only if `enable_cassandra_tracker` is set to `true`. | `number` | `4` | no |
| <a name="input_cassandra_disk_sku"></a> [cassandra\_disk\_sku](#input\_cassandra\_disk\_sku) | Premium disk SKU for each Cassandra node disk (e.g. `P30`, `P40`). Valid only if `enable_cassandra_tracker` is set to `true`. | `string` | `"P30"` | no |
| <a name="input_cassandra_node_count"></a> [cassandra\_node\_count](#input\_cassandra\_node\_count) | Number of Cassandra nodes per data center. Azure Managed Instance for Apache Cassandra requires at least 3. Valid only if `enable_cassandra_tracker` is set to `true`. | `number` | `3` | no |
| <a name="input_cassandra_sku"></a> [cassandra\_sku](#input\_cassandra\_sku) | VM SKU for each Cassandra node. Azure Managed Cassandra only accepts a fixed list of 8-core-and-larger SKUs (see validation). Default `Standard_D8s_v5` is the cheapest supported option for dev/demo; use `Standard_E8s_v5` or larger for production. | `string` | `"Standard_D8s_v5"` | no |
| <a name="input_cassandra_subnet_cidr"></a> [cassandra\_subnet\_cidr](#input\_cassandra\_subnet\_cidr) | CIDR for the delegated subnet hosting Azure Managed Instance for Apache Cassandra. Must be /26 or larger. Valid only if `enable_cassandra_tracker` is set to `true`. | `string` | `"10.0.20.0/26"` | no |
| <a name="input_cassandra_version"></a> [cassandra\_version](#input\_cassandra\_version) | Apache Cassandra major version for the Managed Instance cluster. Valid only if `enable_cassandra_tracker` is set to `true`. | `string` | `"4.0"` | no |
| <a name="input_ces_source_sql_server"></a> [ces\_source\_sql\_server](#input\_ces\_source\_sql\_server) | Azure SQL Server (in the same subscription) whose system-assigned managed identity is granted `Azure Event Hubs Data Sender` on each hub. The server must already exist at apply time and have system-assigned MI enabled. Set to `null` to fall back to the local `module.sql_server` (when `enable_sql_server = true`) or to skip the role assignment entirely. Valid only if `enable_event_hub` is set to `true`. | <pre>object({<br/>    name                = string<br/>    resource_group_name = string<br/>  })</pre> | `null` | no |
| <a name="input_communication_email_sender_username"></a> [communication\_email\_sender\_username](#input\_communication\_email\_sender\_username) | Identifier used for both (a) the ACS SMTP Username resource (SMTP AUTH login string) and (b) the local-part of the sender address on the Azure-managed domain. Default `martini` yields `martini` as the SMTP login and `martini@<random>.azurecomm.net` as the From address. Valid only if `enable_communication_services_email` is set to `true`. | `string` | `"martini"` | no |
| <a name="input_communication_email_smtp_entra_app"></a> [communication\_email\_smtp\_entra\_app](#input\_communication\_email\_smtp\_entra\_app) | Existing Microsoft Entra application used as the SMTP authentication principal against the Communication Services resource. Have your tenant admin create the app (Application Developer is sufficient) in the same tenant as the subscription, then capture: `client_id` (Application (client) ID), `sp_object_id` (Enterprise Application → Object ID, NOT the app registration Object ID), and `client_secret` (value of a client secret you generated on the app). Required when `enable_communication_services_email = true`. | <pre>object({<br/>    client_id     = string<br/>    sp_object_id  = string<br/>    client_secret = string<br/>  })</pre> | `null` | no |
| <a name="input_custom_domain"></a> [custom\_domain](#input\_custom\_domain) | Public FQDN to bind to the Container App's external ingress (e.g. cooper.external.lonti.com). When empty, the app is reachable only on its free *.azurecontainerapps.io FQDN with Microsoft's auto-managed certificate, and no custom-domain or certificate resources are created. Binding a custom domain is a two-phase apply — see custom\_domain\_dns\_ready. | `string` | `""` | no |
| <a name="input_custom_domain_dns_ready"></a> [custom\_domain\_dns\_ready](#input\_custom\_domain\_dns\_ready) | Two-phase-apply gate for binding custom\_domain. Leave false on the first<br/>apply: the Container App is created and the custom\_domain\_dns\_records output<br/>lists the CNAME + asuid TXT records to create. Create those records, then set<br/>this true and re-apply. The second apply issues the free DigiCert managed<br/>certificate (validated by DigiCert reaching the public FQDN) and binds it to<br/>the domain via SNI. Ignored when custom\_domain is empty. | `bool` | `false` | no |
| <a name="input_docker_registry_password"></a> [docker\_registry\_password](#input\_docker\_registry\_password) | Docker Hub access token (preferred) or password paired with `docker_registry_username`. | `string` | `""` | no |
| <a name="input_docker_registry_username"></a> [docker\_registry\_username](#input\_docker\_registry\_username) | Docker Hub username used to authenticate image pulls and avoid anonymous rate limits. Leave empty to pull anonymously. | `string` | `""` | no |
| <a name="input_ecr_source_credentials"></a> [ecr\_source\_credentials](#input\_ecr\_source\_credentials) | Private AWS ECR source for the Martini Designer image. When set, an Azure Container Registry is provisioned as a pull-through cache and the Designer ACI pulls from there instead of Docker Hub. Leave null to use the public Docker Hub image. | <pre>object({<br/>    account_id = string<br/>    region     = string<br/>    access_key = string<br/>    secret_key = string<br/>    repository = optional(string, "lontiplatform/martini-designer-online")<br/>  })</pre> | `null` | no |
| <a name="input_enable_cassandra_tracker"></a> [enable\_cassandra\_tracker](#input\_enable\_cassandra\_tracker) | Should Martini use Azure Managed Instance for Apache Cassandra as the tracker backend? | `bool` | `false` | no |
| <a name="input_enable_communication_services_email"></a> [enable\_communication\_services\_email](#input\_enable\_communication\_services\_email) | Provision Azure Communication Services Email with the Azure-managed sender subdomain (<random>.azurecomm.net) and expose SMTP relay credentials (smtp.azurecomm.net:587) to the Martini ACIs. Includes an Entra app registration used as the SMTP principal with the `Contributor` role on the Communication Services resource. Subject to the Azure-managed-domain quota (~100 emails/day, 10 recipients per message); use a custom verified domain for production volume. | `bool` | `true` | no |
| <a name="input_enable_designer"></a> [enable\_designer](#input\_enable\_designer) | Deploy Martini Designer as a single-instance ACI instead of the runtime. Mutually exclusive with the runtime deployment. | `bool` | `false` | no |
| <a name="input_enable_event_hub"></a> [enable\_event\_hub](#input\_enable\_event\_hub) | Provision an Azure Event Hubs namespace and the hub instances declared in `event_hubs` as the destination for Azure SQL Change Event Streaming (CES). The source SQL Server is identified by `ces_source_sql_server`; if that variable is null and `enable_sql_server = true`, the local SQL Server's system-assigned managed identity is used as fallback. Otherwise the namespace is created with no role assignment. | `bool` | `false` | no |
| <a name="input_enable_log_analytics"></a> [enable\_log\_analytics](#input\_enable\_log\_analytics) | Provision a Log Analytics workspace and stream container stdout/stderr from the Martini ACIs into it via the diagnostics.log\_analytics block. Workspace uses the PerGB2018 SKU with 30-day retention. Required for the log-based alerts. | `bool` | `false` | no |
| <a name="input_enable_sql_server"></a> [enable\_sql\_server](#input\_enable\_sql\_server) | Should Martini use SQL Server database? | `bool` | `false` | no |
| <a name="input_event_hub_capacity"></a> [event\_hub\_capacity](#input\_event\_hub\_capacity) | Throughput units (Standard) or processing units (Premium) for the namespace. Ignored for Basic. Valid only if `enable_event_hub` is set to `true`. | `number` | `1` | no |
| <a name="input_event_hub_namespace_sku"></a> [event\_hub\_namespace\_sku](#input\_event\_hub\_namespace\_sku) | SKU tier for the Event Hubs namespace. Must be `Standard` or higher for Martini's Kafka-protocol CES consumer — Basic-tier namespaces do not expose port 9093. Valid only if `enable_event_hub` is set to `true`. | `string` | `"Standard"` | no |
| <a name="input_event_hubs"></a> [event\_hubs](#input\_event\_hubs) | Event Hub instances to create on the namespace, keyed by name. Each entry sets `partition_count` and `message_retention` (days). Each hub receives an `Azure Event Hubs Data Sender` grant for the resolved CES source identity (see `ces_source_sql_server`), if any. Valid only if `enable_event_hub` is set to `true`. | <pre>map(object({<br/>    partition_count   = number<br/>    message_retention = number<br/>  }))</pre> | `{}` | no |
| <a name="input_existing_vnet"></a> [existing\_vnet](#input\_existing\_vnet) | Reference to a pre-existing VNet to deploy workload subnets into. When set,<br/>the template skips creating its own VNet/NAT gateway and instead creates the<br/>per-workload subnets (ACI, Container Apps, and — when<br/>enable\_cassandra\_tracker = true — Cassandra MI) directly inside the named<br/>VNet via azurerm\_subnet. The Terraform principal must hold<br/>Microsoft.Network/virtualNetworks/subnets/write on the VNet.<br/><br/>When null (default), the template creates a brand-new VNet plus a NAT gateway<br/>using vnet\_address\_space / private\_subnet\_cidrs / aca\_subnet\_cidr /<br/>cassandra\_subnet\_cidr (current behaviour, preserved). | <pre>object({<br/>    name                = string<br/>    resource_group_name = string<br/>  })</pre> | `null` | no |
| <a name="input_martini_cpu"></a> [martini\_cpu](#input\_martini\_cpu) | Number of CPU cores to allocate for the application. | `number` | `2` | no |
| <a name="input_martini_home_path"></a> [martini\_home\_path](#input\_martini\_home\_path) | Path to the Martini workspace inside the container image. Default matches the official lontiplatform/martini-server-runtime image. | `string` | `"/data"` | no |
| <a name="input_martini_memory"></a> [martini\_memory](#input\_martini\_memory) | Amount of memory (in GB) to allocate for the application | `number` | `4` | no |
| <a name="input_martini_node_count"></a> [martini\_node\_count](#input\_martini\_node\_count) | Number of Martini runtime container app replicas to run. | `number` | `1` | no |
| <a name="input_martini_premium_share_quota_gb"></a> [martini\_premium\_share\_quota\_gb](#input\_martini\_premium\_share\_quota\_gb) | Provisioned capacity (GiB) applied uniformly to every ACI-mounted Premium FileStorage share. Premium shares bill on provisioned GiB at ~$0.16/GiB-month (LRS, Central US); 100 is the minimum Azure will accept. | `number` | `100` | no |
| <a name="input_martini_version"></a> [martini\_version](#input\_martini\_version) | Tag of the Martini Docker image to deploy. Applied to the runtime image or the designer image depending on `enable_designer`. | `string` | `"2.7.2"` | no |
| <a name="input_martini_workspace_license"></a> [martini\_workspace\_license](#input\_martini\_workspace\_license) | Full license text to be used with Martini | `string` | n/a | yes |
| <a name="input_name_suffix"></a> [name\_suffix](#input\_name\_suffix) | Suffix to add to the resources' names | `string` | `""` | no |
| <a name="input_private_subnet_cidrs"></a> [private\_subnet\_cidrs](#input\_private\_subnet\_cidrs) | Mode A only — ignored when existing\_vnet is set. A list of prefixes for private subnets. | `list(string)` | <pre>[<br/>  "10.0.11.0/24",<br/>  "10.0.12.0/24"<br/>]</pre> | no |
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
| <a name="output_cassandra_cluster_name"></a> [cassandra\_cluster\_name](#output\_cassandra\_cluster\_name) | n/a |
| <a name="output_cassandra_contact_point"></a> [cassandra\_contact\_point](#output\_cassandra\_contact\_point) | n/a |
| <a name="output_cassandra_port"></a> [cassandra\_port](#output\_cassandra\_port) | n/a |
| <a name="output_communication_services_email_domain"></a> [communication\_services\_email\_domain](#output\_communication\_services\_email\_domain) | n/a |
| <a name="output_communication_services_sender_address"></a> [communication\_services\_sender\_address](#output\_communication\_services\_sender\_address) | n/a |
| <a name="output_communication_services_smtp_host"></a> [communication\_services\_smtp\_host](#output\_communication\_services\_smtp\_host) | n/a |
| <a name="output_communication_services_smtp_port"></a> [communication\_services\_smtp\_port](#output\_communication\_services\_smtp\_port) | n/a |
| <a name="output_custom_domain_dns_records"></a> [custom\_domain\_dns\_records](#output\_custom\_domain\_dns\_records) | The exact DNS records to create in the zone that owns custom\_domain, then set custom\_domain\_dns\_ready = true and re-apply. Null when custom\_domain is empty. |
| <a name="output_custom_domain_url"></a> [custom\_domain\_url](#output\_custom\_domain\_url) | Public HTTPS URL of the custom domain once the CNAME + asuid TXT records are in place and custom\_domain\_dns\_ready = true has issued and bound the managed certificate. |
| <a name="output_event_hub_names"></a> [event\_hub\_names](#output\_event\_hub\_names) | n/a |
| <a name="output_event_hub_namespace_fqdn"></a> [event\_hub\_namespace\_fqdn](#output\_event\_hub\_namespace\_fqdn) | n/a |
| <a name="output_event_hub_namespace_name"></a> [event\_hub\_namespace\_name](#output\_event\_hub\_namespace\_name) | n/a |
| <a name="output_log_analytics_workspace_id"></a> [log\_analytics\_workspace\_id](#output\_log\_analytics\_workspace\_id) | n/a |
| <a name="output_log_analytics_workspace_name"></a> [log\_analytics\_workspace\_name](#output\_log\_analytics\_workspace\_name) | n/a |
| <a name="output_martini_ingress_fqdn"></a> [martini\_ingress\_fqdn](#output\_martini\_ingress\_fqdn) | Default *.azurecontainerapps.io FQDN of the Martini app's external ingress (the app's base URL when no custom domain is bound). |
| <a name="output_resource_group_location"></a> [resource\_group\_location](#output\_resource\_group\_location) | n/a |
| <a name="output_resource_group_name"></a> [resource\_group\_name](#output\_resource\_group\_name) | n/a |
| <a name="output_subnet_prefixes"></a> [subnet\_prefixes](#output\_subnet\_prefixes) | n/a |
<!-- END_TF_DOCS -->