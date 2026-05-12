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
  description = "Number of Martini container instances to run behind the Application Gateway"
  type        = number
  default     = 1

  validation {
    condition     = var.martini_node_count >= 1
    error_message = "node_count must be at least 1."
  }
}

variable "martini_home_path" {
  description = "Path to the Martini workspace inside the container image. Default matches the official lontiplatform/martini-server-runtime image."
  type        = string
  default     = "/data"
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
  default     = 1

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
  description = "SKU tier for the Event Hubs namespace. Valid only if `enable_event_hub` is set to `true`."
  type        = string
  default     = "Basic"

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

// Virtual Network configuration
variable "existing_vnet" {
  description = <<-EOT
    Reference to a pre-existing VNet to deploy workload subnets into. When set,
    the template skips creating its own VNet/NAT/route-table/shared NSG and
    instead creates the per-workload subnets (ACI, App Gateway, and — when
    enable_cassandra_tracker = true — Cassandra MI) directly inside the named
    VNet via azurerm_subnet. The Terraform principal must hold
    Microsoft.Network/virtualNetworks/subnets/write on the VNet.

    When null (default), the template creates a brand-new VNet plus NAT gateway,
    route table, and shared NSG using vnet_address_space / public_subnet_cidrs /
    private_subnet_cidrs / cassandra_subnet_cidr (current behaviour, preserved).
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

variable "appgw_subnet_cidr" {
  description = "CIDR for the Application Gateway dedicated subnet inside the existing VNet (/26 or larger recommended for v2). Required when existing_vnet is set; ignored otherwise."
  type        = string
  default     = null

  validation {
    condition     = var.appgw_subnet_cidr == null || can(cidrhost(var.appgw_subnet_cidr, 0))
    error_message = "appgw_subnet_cidr must be a valid CIDR block."
  }

  validation {
    condition     = var.appgw_subnet_cidr == null || tonumber(regex("/(\\d+)$", var.appgw_subnet_cidr)[0]) <= 26
    error_message = "appgw_subnet_cidr prefix length must be /26 or larger (prefix number <= 26)."
  }
}

variable "byo_vnet_route_table_id" {
  description = "Optional ID of a pre-existing route table to associate with the ACI and Cassandra subnets when existing_vnet is set. Leave null to use Azure system routes. Ignored when existing_vnet is null."
  type        = string
  default     = null
}

variable "byo_vnet_workload_nsg_id" {
  description = "Optional ID of a pre-existing NSG to associate with the ACI and Cassandra subnets when existing_vnet is set. The Application Gateway subnet always gets a dedicated NSG created by this template. Ignored when existing_vnet is null."
  type        = string
  default     = null
}

variable "vnet_address_space" {
  description = "Mode A only — ignored when existing_vnet is set. Virtual Network CIDR"
  type        = list(string)
  default     = ["10.0.0.0/18"]
}

variable "public_subnet_cidrs" {
  description = "Mode A only — ignored when existing_vnet is set. A list of prefixes for public subnets."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Mode A only — ignored when existing_vnet is set. A list of prefixes for public subnets."
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

