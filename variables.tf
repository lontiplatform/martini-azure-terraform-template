// General configuration
variable "rg_location" {
  type        = string
  description = "Azure region to deploy resources into"
}

variable "name_suffix" {
  description = "Suffix to add to the resources' names"
  default     = ""
  type        = string
}

variable "tags" {
  description = "Common tags for components created in the infrastructure"
  type        = map(string)

  default = {
    Application = "Martini"
    Repository  = "https://github.com/lontiplatform/martini-azure-terraform-template"
  }
}

// Application configuration
variable "martini_workspace_license" {
  description = "Full license text to be used with Martini"
  type        = string
}

// ACI configuration
variable "enable_designer" {
  description = "Deploy Martini Designer as a single-instance ACI instead of the runtime. Mutually exclusive with the runtime deployment."
  type        = bool
  default     = false
}

variable "martini_version" {
  description = "Tag of the Martini Docker image to deploy. Applied to the runtime image or the designer image depending on `enable_designer`."
  type        = string
  default     = "2.7.2"
}

variable "docker_registry_username" {
  description = "Docker Hub username used to authenticate image pulls and avoid anonymous rate limits. Leave empty to pull anonymously."
  type        = string
  default     = ""
}

variable "docker_registry_password" {
  description = "Docker Hub access token (preferred) or password paired with `docker_registry_username`."
  type        = string
  default     = ""
  sensitive   = true

  validation {
    condition     = (trimspace(var.docker_registry_username) == "") == (trimspace(var.docker_registry_password) == "")
    error_message = "docker_registry_username and docker_registry_password must either both be set or both be empty."
  }
}

variable "ecr_source_credentials" {
  description = "Private AWS ECR source for the Martini Designer image. When set, an Azure Container Registry is provisioned as a pull-through cache and the Designer ACI pulls from there instead of Docker Hub. Leave null to use the public Docker Hub image."
  type = object({
    account_id = string
    region     = string
    access_key = string
    secret_key = string
    repository = optional(string, "lontiplatform/martini-designer-online")
  })
  default   = null
  sensitive = true

  validation {
    condition = var.ecr_source_credentials == null || (
      trimspace(var.ecr_source_credentials.account_id) != "" &&
      trimspace(var.ecr_source_credentials.region) != "" &&
      trimspace(var.ecr_source_credentials.access_key) != "" &&
      trimspace(var.ecr_source_credentials.secret_key) != ""
    )
    error_message = "ecr.account_id, region, access_key, and secret_key must all be non-empty when ecr is set."
  }
}

variable "martini_cpu" {
  description = "Number of CPU cores to allocate for the application."
  type        = number
  default     = 2
}

variable "martini_memory" {
  description = "Amount of memory (in GB) to allocate for the application"
  type        = number
  default     = 4
}

variable "martini_node_count" {
  description = "Number of Martini runtime container app replicas to run."
  type        = number
  default     = 1

  validation {
    condition     = var.martini_node_count >= 1
    error_message = "martini_node_count must be at least 1."
  }
}

variable "martini_home_path" {
  description = "Path to the Martini workspace inside the container image. Default matches the official lontiplatform/martini-server-runtime image."
  type        = string
  default     = "/data"
}

variable "enable_log_analytics" {
  description = "Provision a Log Analytics workspace and stream container stdout/stderr from the Martini ACIs into it via the diagnostics.log_analytics block. Workspace uses the PerGB2018 SKU with 30-day retention. Required for the log-based alerts."
  type        = bool
  default     = false
}

variable "alert_emails" {
  description = "List of email addresses that receive every alert fired by the action group. Each address becomes a separate email_receiver. Leave empty to provision the action group with no receivers (alerts still fire but go nowhere)."
  type        = list(string)
  default     = []
}

variable "martini_premium_share_quota_gb" {
  description = "Provisioned capacity (GiB) applied uniformly to every ACI-mounted Premium FileStorage share. Premium shares bill on provisioned GiB at ~$0.16/GiB-month (LRS, Central US); 100 is the minimum Azure will accept."
  type        = number
  default     = 100

  validation {
    condition     = var.martini_premium_share_quota_gb >= 100
    error_message = "martini_premium_share_quota_gb must be at least 100 (Azure Premium FileStorage minimum)."
  }
}

// SQL Server configuration
variable "enable_sql_server" {
  description = "Should Martini use SQL Server database?"
  type        = bool
  default     = false
}

variable "sql_server_admin_username" {
  description = "Username to set in the SQl Server. Valid only if `enable_sql_server` is set to `true`"
  type        = string
  default     = null
}

variable "sql_server_version" {
  description = "The RDS engine version to use. Valid only if `enable_sql_server` is set to `true`"
  type        = string
  default     = null
}

variable "sql_database_name" {
  description = "Name of the SQL database. Valid only if `enable_sql_server` is set to `true`"
  type        = string
  default     = "martini"
}

variable "sql_max_size_gb" {
  description = "The max size of the database in gigabytes."
  type        = number
  default     = 50
}

// Cassandra (Managed Instance) tracker configuration
variable "enable_cassandra_tracker" {
  description = "Should Martini use Azure Managed Instance for Apache Cassandra as the tracker backend?"
  type        = bool
  default     = false
}

variable "cassandra_subnet_cidr" {
  description = "CIDR for the delegated subnet hosting Azure Managed Instance for Apache Cassandra. Must be /26 or larger. Valid only if `enable_cassandra_tracker` is set to `true`."
  type        = string
  default     = "10.0.20.0/26"

  validation {
    condition     = can(cidrhost(var.cassandra_subnet_cidr, 0))
    error_message = "cassandra_subnet_cidr must be a valid CIDR block."
  }

  validation {
    condition     = tonumber(regex("/(\\d+)$", var.cassandra_subnet_cidr)[0]) <= 26
    error_message = "cassandra_subnet_cidr prefix length must be /26 or larger (prefix number <= 26)."
  }
}

variable "cassandra_version" {
  description = "Apache Cassandra major version for the Managed Instance cluster. Valid only if `enable_cassandra_tracker` is set to `true`."
  type        = string
  default     = "4.0"

  validation {
    condition     = contains(["3.11", "4.0"], var.cassandra_version)
    error_message = "cassandra_version must be one of: 3.11, 4.0."
  }
}

variable "cassandra_node_count" {
  description = "Number of Cassandra nodes per data center. Azure Managed Instance for Apache Cassandra requires at least 3. Valid only if `enable_cassandra_tracker` is set to `true`."
  type        = number
  default     = 3

  validation {
    condition     = var.cassandra_node_count >= 3
    error_message = "cassandra_node_count must be at least 3 (Azure Managed Instance minimum)."
  }
}

variable "cassandra_sku" {
  description = "VM SKU for each Cassandra node. Azure Managed Cassandra only accepts a fixed list of 8-core-and-larger SKUs (see validation). Default `Standard_D8s_v5` is the cheapest supported option for dev/demo; use `Standard_E8s_v5` or larger for production."
  type        = string
  default     = "Standard_D8s_v5"

  validation {
    condition = contains([
      "Standard_DS13_v2", "Standard_DS14_v2",
      "Standard_D8s_v4", "Standard_D16s_v4", "Standard_D32s_v4",
      "Standard_E8s_v4", "Standard_E16s_v4", "Standard_E20s_v4", "Standard_E32s_v4",
      "Standard_D8s_v5", "Standard_D16s_v5", "Standard_D32s_v5",
      "Standard_D8as_v5", "Standard_D16as_v5", "Standard_D32as_v5",
      "Standard_E8s_v5", "Standard_E16s_v5", "Standard_E20s_v5", "Standard_E32s_v5",
      "Standard_E8as_v5", "Standard_E16as_v5", "Standard_E20as_v5", "Standard_E32as_v5",
      "Standard_L8s_v3", "Standard_L16s_v3", "Standard_L32s_v3",
      "Standard_L8as_v3", "Standard_L16as_v3", "Standard_L32as_v3",
    ], var.cassandra_sku)
    error_message = "cassandra_sku must be one of the SKUs supported by Azure Managed Cassandra. Per-region support may be narrower; check the Azure portal if apply still fails."
  }
}

variable "cassandra_disk_count" {
  description = "Number of premium managed disks attached to each Cassandra node. Valid only if `enable_cassandra_tracker` is set to `true`."
  type        = number
  default     = 4

  validation {
    condition     = var.cassandra_disk_count >= 1
    error_message = "cassandra_disk_count must be at least 1."
  }
}

variable "cassandra_disk_sku" {
  description = "Premium disk SKU for each Cassandra node disk (e.g. `P30`, `P40`). Valid only if `enable_cassandra_tracker` is set to `true`."
  type        = string
  default     = "P30"

  validation {
    condition     = trimspace(var.cassandra_disk_sku) != ""
    error_message = "cassandra_disk_sku must not be empty."
  }
}

// Event Hubs configuration (destination for Azure SQL Change Event Streaming)
variable "enable_event_hub" {
  description = "Provision an Azure Event Hubs namespace and the hub instances declared in `event_hubs` as the destination for Azure SQL Change Event Streaming (CES). The source SQL Server is identified by `ces_source_sql_server`; if that variable is null and `enable_sql_server = true`, the local SQL Server's system-assigned managed identity is used as fallback. Otherwise the namespace is created with no role assignment."
  type        = bool
  default     = false
}

variable "event_hub_namespace_sku" {
  description = "SKU tier for the Event Hubs namespace. Must be `Standard` or higher for Martini's Kafka-protocol CES consumer — Basic-tier namespaces do not expose port 9093. Valid only if `enable_event_hub` is set to `true`."
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.event_hub_namespace_sku)
    error_message = "event_hub_namespace_sku must be one of: Basic, Standard, Premium."
  }
}

variable "event_hub_capacity" {
  description = "Throughput units (Standard) or processing units (Premium) for the namespace. Ignored for Basic. Valid only if `enable_event_hub` is set to `true`."
  type        = number
  default     = 1

  validation {
    condition     = var.event_hub_capacity >= 1 && var.event_hub_capacity <= 20
    error_message = "event_hub_capacity must be between 1 and 20."
  }
}

variable "event_hubs" {
  description = "Event Hub instances to create on the namespace, keyed by name. Each entry sets `partition_count` and `message_retention` (days). Each hub receives an `Azure Event Hubs Data Sender` grant for the resolved CES source identity (see `ces_source_sql_server`), if any. Valid only if `enable_event_hub` is set to `true`."
  type = map(object({
    partition_count   = number
    message_retention = number
  }))
  default = {}
}

variable "ces_source_sql_server" {
  description = "Azure SQL Server (in the same subscription) whose system-assigned managed identity is granted `Azure Event Hubs Data Sender` on each hub. The server must already exist at apply time and have system-assigned MI enabled. Set to `null` to fall back to the local `module.sql_server` (when `enable_sql_server = true`) or to skip the role assignment entirely. Valid only if `enable_event_hub` is set to `true`."
  type = object({
    name                = string
    resource_group_name = string
  })
  default = null
}

// Azure Communication Services (Email / SMTP) configuration
variable "enable_communication_services_email" {
  description = "Provision Azure Communication Services Email with the Azure-managed sender subdomain (<random>.azurecomm.net) and expose SMTP relay credentials (smtp.azurecomm.net:587) to the Martini ACIs. Includes an Entra app registration used as the SMTP principal with the `Contributor` role on the Communication Services resource. Subject to the Azure-managed-domain quota (~100 emails/day, 10 recipients per message); use a custom verified domain for production volume."
  type        = bool
  default     = true
}

variable "communication_email_sender_username" {
  description = "Identifier used for both (a) the ACS SMTP Username resource (SMTP AUTH login string) and (b) the local-part of the sender address on the Azure-managed domain. Default `martini` yields `martini` as the SMTP login and `martini@<random>.azurecomm.net` as the From address. Valid only if `enable_communication_services_email` is set to `true`."
  type        = string
  default     = "martini"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,64}$", var.communication_email_sender_username))
    error_message = "communication_email_sender_username must be 1-64 chars of letters, digits, or hyphens (intersection of the SMTP Username resource constraint `^[a-zA-Z0-9-]+$` and the email local-part length cap)."
  }
}

variable "communication_email_smtp_entra_app" {
  description = "Existing Microsoft Entra application used as the SMTP authentication principal against the Communication Services resource. Have your tenant admin create the app (Application Developer is sufficient) in the same tenant as the subscription, then capture: `client_id` (Application (client) ID), `sp_object_id` (Enterprise Application → Object ID, NOT the app registration Object ID), and `client_secret` (value of a client secret you generated on the app). Required when `enable_communication_services_email = true`."
  type = object({
    client_id     = string
    sp_object_id  = string
    client_secret = string
  })
  default   = null
  sensitive = true

  validation {
    condition     = var.communication_email_smtp_entra_app == null || alltrue([for v in [try(var.communication_email_smtp_entra_app.client_id, ""), try(var.communication_email_smtp_entra_app.sp_object_id, ""), try(var.communication_email_smtp_entra_app.client_secret, "")] : trimspace(v) != ""])
    error_message = "communication_email_smtp_entra_app fields client_id, sp_object_id, and client_secret must all be non-empty."
  }

  validation {
    condition     = !var.enable_communication_services_email || var.communication_email_smtp_entra_app != null
    error_message = "communication_email_smtp_entra_app must be set when enable_communication_services_email is true. Have your tenant admin pre-create the Entra app and supply { client_id, sp_object_id, client_secret }."
  }
}

// Virtual Network configuration
variable "existing_vnet" {
  description = <<-EOT
    Reference to a pre-existing VNet to deploy workload subnets into. When set,
    the template skips creating its own VNet/NAT gateway and instead creates the
    per-workload subnets (ACI, Container Apps, and — when
    enable_cassandra_tracker = true — Cassandra MI) directly inside the named
    VNet via azurerm_subnet. The Terraform principal must hold
    Microsoft.Network/virtualNetworks/subnets/write on the VNet.

    When null (default), the template creates a brand-new VNet plus a NAT gateway
    using vnet_address_space / private_subnet_cidrs / aca_subnet_cidr /
    cassandra_subnet_cidr (current behaviour, preserved).
  EOT
  type = object({
    name                = string
    resource_group_name = string
  })
  default = null
}

variable "aci_subnet_cidr" {
  description = "CIDR for the ACI delegated subnet inside the existing VNet. Required when existing_vnet is set; ignored otherwise."
  type        = string
  default     = null

  validation {
    condition     = var.aci_subnet_cidr == null || can(cidrhost(var.aci_subnet_cidr, 0))
    error_message = "aci_subnet_cidr must be a valid CIDR block."
  }
}

variable "aca_subnet_cidr" {
  description = "CIDR for the Azure Container Apps delegated subnet. Minimum /27 (32 IPs) for a Workload Profile environment. Required when existing_vnet is set; in Mode A the subnet is created from this CIDR via the AVM module."
  type        = string
  default     = null

  validation {
    condition     = var.aca_subnet_cidr == null || can(cidrhost(var.aca_subnet_cidr, 0))
    error_message = "aca_subnet_cidr must be a valid CIDR block."
  }

  validation {
    condition     = var.aca_subnet_cidr == null || tonumber(regex("/(\\d+)$", var.aca_subnet_cidr)[0]) <= 27
    error_message = "aca_subnet_cidr prefix length must be /27 or larger (prefix number <= 27)."
  }
}

variable "byo_vnet_route_table_id" {
  description = "Optional ID of a pre-existing route table to associate with the ACI and Cassandra subnets when existing_vnet is set. Leave null to use Azure system routes. Ignored when existing_vnet is null."
  type        = string
  default     = null
}

variable "byo_vnet_workload_nsg_id" {
  description = "Optional ID of a pre-existing NSG to associate with the ACI and Cassandra subnets when existing_vnet is set. Ignored when existing_vnet is null."
  type        = string
  default     = null
}

variable "vnet_address_space" {
  description = "Mode A only — ignored when existing_vnet is set. Virtual Network CIDR"
  type        = list(string)
  default     = ["10.0.0.0/18"]
}

variable "private_subnet_cidrs" {
  description = "Mode A only — ignored when existing_vnet is set. A list of prefixes for private subnets."
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

// Custom domain / TLS configuration
variable "custom_domain" {
  description = "Public FQDN to bind to the Container App's external ingress (e.g. cooper.external.lonti.com). When empty, the app is reachable only on its free *.azurecontainerapps.io FQDN with Microsoft's auto-managed certificate, and no custom-domain or certificate resources are created. Binding a custom domain is a two-phase apply — see custom_domain_dns_ready."
  type        = string
  default     = ""
}

variable "custom_domain_dns_ready" {
  description = <<-EOT
    Two-phase-apply gate for binding custom_domain. Leave false on the first
    apply: the Container App is created and the custom_domain_dns_records output
    lists the CNAME + asuid TXT records to create. Create those records, then set
    this true and re-apply. The second apply issues the free DigiCert managed
    certificate (validated by DigiCert reaching the public FQDN) and binds it to
    the domain via SNI. Ignored when custom_domain is empty.
  EOT
  type        = bool
  default     = false
}

