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
variable "aci_docker_image_url" {
  description = "Docker image repository for the Martini runtime (without tag). The tag is set via `martini_version`."
  type        = string
  default     = "lontiplatform/martini-server-runtime"
}

variable "enable_designer" {
  description = "Deploy `lontiplatform/martini-designer-online` as a single-instance ACI instead of the runtime. Mutually exclusive with the runtime deployment."
  type        = bool
  default     = false
}

variable "designer_docker_image_url" {
  description = "Docker image repository for the Martini designer (without tag). The tag is set via `martini_version`. Valid only if `enable_designer` is set to `true`."
  type        = string
  default     = "lontiplatform/martini-designer-online"
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

variable "cpu" {
  description = "Number of CPU cores to allocate for the application."
  type        = number
  default     = 2
}

variable "memory" {
  description = "Amount of memory (in GB) to allocate for the application"
  type        = number
  default     = 4
}

variable "node_count" {
  description = "Number of Martini container instances to run behind the Application Gateway"
  type        = number
  default     = 1

  validation {
    condition     = var.node_count >= 1
    error_message = "node_count must be at least 1."
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

variable "max_size_gb" {
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

variable "martini_home_path" {
  description = "Path to the Martini workspace inside the container image. Default matches the official lontiplatform/martini-server-runtime image."
  type        = string
  default     = "/data"
}

// Service Bus configuration
variable "enable_service_bus" {
  description = "Should an Azure Service Bus namespace be provisioned for inbound messaging (e.g. Azure SQL CES -> Martini)?"
  type        = bool
  default     = false
}

variable "service_bus_sku" {
  description = "SKU tier for the Service Bus namespace. Basic does not support topics. Valid only if `enable_service_bus` is set to `true`."
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.service_bus_sku)
    error_message = "service_bus_sku must be one of: Basic, Standard, Premium."
  }
}

variable "service_bus_capacity" {
  description = "Messaging units for the Premium SKU. Ignored for Basic/Standard. Valid only if `enable_service_bus` is set to `true`."
  type        = number
  default     = 1

  validation {
    condition     = contains([1, 2, 4, 8, 16], var.service_bus_capacity)
    error_message = "service_bus_capacity must be one of: 1, 2, 4, 8, 16."
  }
}

variable "service_bus_premium_messaging_partitions" {
  description = "Messaging partitions for the Premium SKU. Ignored for Basic/Standard. Valid only if `enable_service_bus` is set to `true`."
  type        = number
  default     = 1

  validation {
    condition     = contains([1, 2, 4], var.service_bus_premium_messaging_partitions)
    error_message = "service_bus_premium_messaging_partitions must be one of: 1, 2, 4."
  }
}

variable "service_bus_queues" {
  description = "Queue names to create on the namespace. Valid only if `enable_service_bus` is set to `true`."
  type        = list(string)
  default     = []
}

variable "service_bus_topics" {
  description = "Topic names to create on the namespace. Each topic gets a single subscription named `martini`. Requires `service_bus_sku` of `Standard` or `Premium`. Valid only if `enable_service_bus` is set to `true`."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.service_bus_topics) == 0 || var.service_bus_sku != "Basic"
    error_message = "service_bus_topics requires service_bus_sku = Standard or Premium (Basic does not support topics)."
  }
}

// Event Hubs configuration (destination for Azure SQL Change Event Streaming)
variable "enable_event_hub" {
  description = "Should an Azure Event Hubs namespace be provisioned as the destination for Azure SQL Change Event Streaming (CES)? Pair with `enable_sql_server = true` so the SQL Server's managed identity can be granted `Azure Event Hubs Data Sender` on the hub instances."
  type        = bool
  default     = false
}

variable "event_hub_namespace_sku" {
  description = "SKU tier for the Event Hubs namespace. Valid only if `enable_event_hub` is set to `true`."
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
  description = "Event Hub instances to create on the namespace, keyed by name. Each entry sets `partition_count` and `message_retention` (days). The SQL Server managed identity is granted `Azure Event Hubs Data Sender` on each hub. Valid only if `enable_event_hub` is set to `true`."
  type = map(object({
    partition_count   = number
    message_retention = number
  }))
  default = {}
}

// Virtual Network configuration
variable "vnet_address_space" {
  description = "Virtual Network CIDR"
  type        = list(string)
  default     = ["10.0.0.0/18"]
}

variable "public_subnet_cidrs" {
  description = "A list of prefixes for public subnets."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "A list of prefixes for public subnets."
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

// Custom-domain TLS via acmebot
variable "custom_domain" {
  description = "Public hostname the Application Gateway should serve (e.g. `martini.example.com`). When set, deploys acmebot and issues a Let's Encrypt certificate into the existing Key Vault. When null, the Application Gateway keeps its self-signed certificate on the `*.cloudapp.azure.com` FQDN."
  type        = string
  default     = null
}

variable "appgw_use_kv_cert" {
  description = "When true, the Application Gateway HTTPS listener references the Key-Vault-stored certificate via the AppGW user-assigned identity. Flip to true after the certificate has been issued (typically on a second `terraform apply`)."
  type        = bool
  default     = false

  validation {
    condition     = !var.appgw_use_kv_cert || var.custom_domain != null
    error_message = "appgw_use_kv_cert = true requires custom_domain to be set."
  }
}

variable "acme_contact_email" {
  description = "Contact email registered with the ACME CA (Let's Encrypt). Required when `custom_domain` is set."
  type        = string
  default     = null

  validation {
    condition     = var.custom_domain == null || (var.acme_contact_email != null && length(trimspace(var.acme_contact_email)) > 0)
    error_message = "acme_contact_email is required when custom_domain is set."
  }
}

variable "acme_endpoint" {
  description = "ACME directory endpoint. Defaults to Let's Encrypt production. Use `https://acme-staging-v02.api.letsencrypt.org/directory` when iterating to avoid hitting rate limits."
  type        = string
  default     = "https://acme-v02.api.letsencrypt.org/directory"
}

variable "acmebot_dns_provider" {
  description = "DNS provider used by acmebot for the ACME DNS-01 challenge. Set exactly one of the optional fields. Required when `custom_domain` is set unless the user is wiring a provider via `acmebot_dns_provider` in another way."
  sensitive   = true

  type = object({
    cloudflare = optional(object({
      api_token = string
    }))
    route_53 = optional(object({
      access_key = string
      secret_key = string
      region     = string
    }))
    azure_dns = optional(object({
      subscription_id = string
    }))
    google_dns = optional(object({
      key_file64 = string
    }))
    go_daddy = optional(object({
      api_key    = string
      api_secret = string
    }))
    gandi = optional(object({
      api_key = string
    }))
    dns_made_easy = optional(object({
      api_key    = string
      secret_key = string
    }))
  })
  default = null

  validation {
    condition = var.acmebot_dns_provider == null || length(compact([
      var.acmebot_dns_provider.cloudflare == null ? "" : "cloudflare",
      var.acmebot_dns_provider.route_53 == null ? "" : "route_53",
      var.acmebot_dns_provider.azure_dns == null ? "" : "azure_dns",
      var.acmebot_dns_provider.google_dns == null ? "" : "google_dns",
      var.acmebot_dns_provider.go_daddy == null ? "" : "go_daddy",
      var.acmebot_dns_provider.gandi == null ? "" : "gandi",
      var.acmebot_dns_provider.dns_made_easy == null ? "" : "dns_made_easy",
    ])) == 1
    error_message = "Set exactly one of cloudflare, route_53, azure_dns, google_dns, go_daddy, gandi, dns_made_easy on acmebot_dns_provider."
  }
}

variable "acmebot_allowed_ips" {
  description = "Optional IP allowlist for the acmebot Function App. When empty, the Function App is reachable from any IP (its endpoints are anonymous — acmebot relies on Easy Auth or this allowlist for access control). Recommended to restrict to the apply host / CI runner range when not using Easy Auth."
  type        = list(string)
  default     = []
}