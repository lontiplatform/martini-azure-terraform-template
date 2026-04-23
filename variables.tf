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
  description = "Docker image repository for the application (without tag). The tag is set via `martini_runtime_version`."
  type        = string
  default     = "lontiplatform/martini-server-runtime"
}

variable "martini_runtime_version" {
  description = "Tag of the Martini runtime Docker image to deploy."
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
  description = "VM SKU for each Cassandra node. Default `Standard_E2s_v5` is the cheapest Managed-Instance-supported SKU for dev/demo; use `Standard_E8s_v5` or larger for production. Valid only if `enable_cassandra_tracker` is set to `true`."
  type        = string
  default     = "Standard_E2s_v5"

  validation {
    condition     = trimspace(var.cassandra_sku) != ""
    error_message = "cassandra_sku must not be empty."
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