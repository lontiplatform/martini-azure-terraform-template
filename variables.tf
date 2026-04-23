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

// Cassandra (Cosmos DB API) tracker configuration
variable "enable_cassandra_tracker" {
  description = "Should Martini use Cosmos DB for Apache Cassandra as the tracker backend?"
  type        = bool
  default     = false
}

variable "cassandra_keyspace_name" {
  description = "Name of the Cassandra keyspace used by the Martini tracker. Valid only if `enable_cassandra_tracker` is set to `true`."
  type        = string
  default     = "tracker"
}

variable "cassandra_throughput" {
  description = "Throughput (RU/s) for the Cassandra keyspace. Must be >= 400, increments of 100. Valid only if `enable_cassandra_tracker` is set to `true`."
  type        = number
  default     = 400

  validation {
    condition     = var.cassandra_throughput >= 400 && var.cassandra_throughput % 100 == 0
    error_message = "cassandra_throughput must be at least 400 RU/s and specified in increments of 100."
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