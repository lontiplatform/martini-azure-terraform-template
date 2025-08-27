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
  description = "A URL to the Docker image used by the application"
  type        = string
  default     = "lontiplatform/martini-server-runtime:latest"
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

// Virtual Network configuration
variable "subnet_prefixes" {
  description = "Prefix for each subnet"
  type        = map(list(string))
  default = {
    public_subnet1  = ["10.0.1.0/24"]
    public_subnet2  = ["10.0.2.0/24"]
    private_subnet1 = ["10.0.11.0/24"]
    private_subnet2 = ["10.0.12.0/24"]
  }
}

variable "vnet_address_space" {
  description = "Virtual Network CIDR"
  type        = list(string)
  default     = ["10.0.0.0/18"]
}