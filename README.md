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
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | ~> 4.37.0 |
| <a name="requirement_local"></a> [local](#requirement\_local) | ~> 2.5 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | 4.37.0 |
| <a name="provider_local"></a> [local](#provider\_local) | 2.8.0 |
| <a name="provider_random"></a> [random](#provider\_random) | 3.8.1 |

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
| [azurerm_cosmosdb_cassandra_cluster.tracker](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/cosmosdb_cassandra_cluster) | resource |
| [azurerm_cosmosdb_cassandra_datacenter.tracker](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/cosmosdb_cassandra_datacenter) | resource |
| [azurerm_key_vault.key_vault](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault) | resource |
| [azurerm_key_vault_secret.cassandra_admin_password](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_secret) | resource |
| [azurerm_key_vault_secret.cassandra_contact_point](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_secret) | resource |
| [azurerm_key_vault_secret.martini_workspace_license](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_secret) | resource |
| [azurerm_key_vault_secret.sql_admin_password](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_secret) | resource |
| [azurerm_key_vault_secret.sql_admin_username](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_secret) | resource |
| [azurerm_public_ip.app_gw_pip](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/public_ip) | resource |
| [azurerm_resource_group.rg](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group) | resource |
| [azurerm_storage_account.conf](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_account) | resource |
| [azurerm_storage_share.conf_db_pool](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_share) | resource |
| [azurerm_storage_share_file.tracker_dbxml](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_share_file) | resource |
| [local_file.tracker_dbxml](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [random_password.admin_password](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [random_password.cassandra_admin](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [random_string.storage_suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [azurerm_client_config.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_aci_docker_image_url"></a> [aci\_docker\_image\_url](#input\_aci\_docker\_image\_url) | Docker image repository for the application (without tag). The tag is set via `martini_runtime_version`. | `string` | `"lontiplatform/martini-server-runtime"` | no |
| <a name="input_cassandra_disk_count"></a> [cassandra\_disk\_count](#input\_cassandra\_disk\_count) | Number of premium managed disks attached to each Cassandra node. Valid only if `enable_cassandra_tracker` is set to `true`. | `number` | `4` | no |
| <a name="input_cassandra_disk_sku"></a> [cassandra\_disk\_sku](#input\_cassandra\_disk\_sku) | Premium disk SKU for each Cassandra node disk (e.g. `P30`, `P40`). Valid only if `enable_cassandra_tracker` is set to `true`. | `string` | `"P30"` | no |
| <a name="input_cassandra_node_count"></a> [cassandra\_node\_count](#input\_cassandra\_node\_count) | Number of Cassandra nodes per data center. Azure Managed Instance for Apache Cassandra requires at least 3. Valid only if `enable_cassandra_tracker` is set to `true`. | `number` | `3` | no |
| <a name="input_cassandra_sku"></a> [cassandra\_sku](#input\_cassandra\_sku) | VM SKU for each Cassandra node. Default `Standard_E2s_v5` is the cheapest Managed-Instance-supported SKU for dev/demo; use `Standard_E8s_v5` or larger for production. Valid only if `enable_cassandra_tracker` is set to `true`. | `string` | `"Standard_E2s_v5"` | no |
| <a name="input_cassandra_subnet_cidr"></a> [cassandra\_subnet\_cidr](#input\_cassandra\_subnet\_cidr) | CIDR for the delegated subnet hosting Azure Managed Instance for Apache Cassandra. Must be /26 or larger. Valid only if `enable_cassandra_tracker` is set to `true`. | `string` | `"10.0.20.0/26"` | no |
| <a name="input_cassandra_version"></a> [cassandra\_version](#input\_cassandra\_version) | Apache Cassandra major version for the Managed Instance cluster. Valid only if `enable_cassandra_tracker` is set to `true`. | `string` | `"4.0"` | no |
| <a name="input_cpu"></a> [cpu](#input\_cpu) | Number of CPU cores to allocate for the application. | `number` | `2` | no |
| <a name="input_docker_registry_password"></a> [docker\_registry\_password](#input\_docker\_registry\_password) | Docker Hub access token (preferred) or password paired with `docker_registry_username`. | `string` | `""` | no |
| <a name="input_docker_registry_username"></a> [docker\_registry\_username](#input\_docker\_registry\_username) | Docker Hub username used to authenticate image pulls and avoid anonymous rate limits. Leave empty to pull anonymously. | `string` | `""` | no |
| <a name="input_enable_cassandra_tracker"></a> [enable\_cassandra\_tracker](#input\_enable\_cassandra\_tracker) | Should Martini use Azure Managed Instance for Apache Cassandra as the tracker backend? | `bool` | `false` | no |
| <a name="input_enable_sql_server"></a> [enable\_sql\_server](#input\_enable\_sql\_server) | Should Martini use SQL Server database? | `bool` | `false` | no |
| <a name="input_martini_home_path"></a> [martini\_home\_path](#input\_martini\_home\_path) | Path to the Martini workspace inside the container image. Default matches the official lontiplatform/martini-server-runtime image. | `string` | `"/data"` | no |
| <a name="input_martini_runtime_version"></a> [martini\_runtime\_version](#input\_martini\_runtime\_version) | Tag of the Martini runtime Docker image to deploy. | `string` | `"2.7.2"` | no |
| <a name="input_martini_workspace_license"></a> [martini\_workspace\_license](#input\_martini\_workspace\_license) | Full license text to be used with Martini | `string` | n/a | yes |
| <a name="input_max_size_gb"></a> [max\_size\_gb](#input\_max\_size\_gb) | The max size of the database in gigabytes. | `number` | `50` | no |
| <a name="input_memory"></a> [memory](#input\_memory) | Amount of memory (in GB) to allocate for the application | `number` | `4` | no |
| <a name="input_name_suffix"></a> [name\_suffix](#input\_name\_suffix) | Suffix to add to the resources' names | `string` | `""` | no |
| <a name="input_node_count"></a> [node\_count](#input\_node\_count) | Number of Martini container instances to run behind the Application Gateway | `number` | `1` | no |
| <a name="input_private_subnet_cidrs"></a> [private\_subnet\_cidrs](#input\_private\_subnet\_cidrs) | A list of prefixes for public subnets. | `list(string)` | <pre>[<br/>  "10.0.11.0/24",<br/>  "10.0.12.0/24"<br/>]</pre> | no |
| <a name="input_public_subnet_cidrs"></a> [public\_subnet\_cidrs](#input\_public\_subnet\_cidrs) | A list of prefixes for public subnets. | `list(string)` | <pre>[<br/>  "10.0.1.0/24",<br/>  "10.0.2.0/24"<br/>]</pre> | no |
| <a name="input_rg_location"></a> [rg\_location](#input\_rg\_location) | Azure region to deploy resources into | `string` | n/a | yes |
| <a name="input_sql_database_name"></a> [sql\_database\_name](#input\_sql\_database\_name) | Name of the SQL database. Valid only if `enable_sql_server` is set to `true` | `string` | `"martini"` | no |
| <a name="input_sql_server_admin_username"></a> [sql\_server\_admin\_username](#input\_sql\_server\_admin\_username) | Username to set in the SQl Server. Valid only if `enable_sql_server` is set to `true` | `string` | `null` | no |
| <a name="input_sql_server_version"></a> [sql\_server\_version](#input\_sql\_server\_version) | The RDS engine version to use. Valid only if `enable_sql_server` is set to `true` | `string` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Common tags for components created in the infrastructure | `map(string)` | <pre>{<br/>  "Application": "Martini",<br/>  "Repository": "https://github.com/lontiplatform/martini-azure-terraform-template"<br/>}</pre> | no |
| <a name="input_vnet_address_space"></a> [vnet\_address\_space](#input\_vnet\_address\_space) | Virtual Network CIDR | `list(string)` | <pre>[<br/>  "10.0.0.0/18"<br/>]</pre> | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_app_gw_url"></a> [app\_gw\_url](#output\_app\_gw\_url) | n/a |
| <a name="output_cassandra_cluster_name"></a> [cassandra\_cluster\_name](#output\_cassandra\_cluster\_name) | n/a |
| <a name="output_cassandra_contact_point"></a> [cassandra\_contact\_point](#output\_cassandra\_contact\_point) | n/a |
| <a name="output_cassandra_port"></a> [cassandra\_port](#output\_cassandra\_port) | n/a |
| <a name="output_resource_group_location"></a> [resource\_group\_location](#output\_resource\_group\_location) | n/a |
| <a name="output_resource_group_name"></a> [resource\_group\_name](#output\_resource\_group\_name) | n/a |
| <a name="output_subnet_prefixes"></a> [subnet\_prefixes](#output\_subnet\_prefixes) | n/a |
<!-- END_TF_DOCS -->