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

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | 4.37.0 |
| <a name="provider_random"></a> [random](#provider\_random) | 3.7.2 |

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
| [azurerm_key_vault.key_vault](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault) | resource |
| [azurerm_key_vault_secret.martini_workspace_license](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_secret) | resource |
| [azurerm_key_vault_secret.sql_admin_password](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_secret) | resource |
| [azurerm_key_vault_secret.sql_admin_username](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_secret) | resource |
| [azurerm_public_ip.app_gw_pip](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/public_ip) | resource |
| [azurerm_resource_group.rg](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group) | resource |
| [random_password.admin_password](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [azurerm_client_config.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_aci_docker_image_url"></a> [aci\_docker\_image\_url](#input\_aci\_docker\_image\_url) | A URL to the Docker image used by the application | `string` | `"lontiplatform/martini-server-runtime:latest"` | no |
| <a name="input_cpu"></a> [cpu](#input\_cpu) | Number of CPU cores to allocate for the application. | `number` | `2` | no |
| <a name="input_enable_sql_server"></a> [enable\_sql\_server](#input\_enable\_sql\_server) | Should Martini use SQL Server database? | `bool` | `false` | no |
| <a name="input_martini_workspace_license"></a> [martini\_workspace\_license](#input\_martini\_workspace\_license) | Full license text to be used with Martini | `string` | n/a | yes |
| <a name="input_max_size_gb"></a> [max\_size\_gb](#input\_max\_size\_gb) | The max size of the database in gigabytes. | `number` | `50` | no |
| <a name="input_memory"></a> [memory](#input\_memory) | Amount of memory (in GB) to allocate for the application | `number` | `4` | no |
| <a name="input_name_suffix"></a> [name\_suffix](#input\_name\_suffix) | Suffix to add to the resources' names | `string` | `""` | no |
| <a name="input_rg_location"></a> [rg\_location](#input\_rg\_location) | Azure region to deploy resources into | `string` | n/a | yes |
| <a name="input_sql_database_name"></a> [sql\_database\_name](#input\_sql\_database\_name) | Name of the SQL database. Valid only if `enable_sql_server` is set to `true` | `string` | `"martini"` | no |
| <a name="input_sql_server_admin_username"></a> [sql\_server\_admin\_username](#input\_sql\_server\_admin\_username) | Username to set in the SQl Server. Valid only if `enable_sql_server` is set to `true` | `string` | `null` | no |
| <a name="input_sql_server_version"></a> [sql\_server\_version](#input\_sql\_server\_version) | The RDS engine version to use. Valid only if `enable_sql_server` is set to `true` | `string` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Common tags for components created in the infrastructure | `map(string)` | <pre>{<br/>  "Application": "Martini",<br/>  "Repository": "https://github.com/lontiplatform/martini-azure-terraform-template"<br/>}</pre> | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_app_gw_url"></a> [app\_gw\_url](#output\_app\_gw\_url) | Application Gateway's URL |
| <a name="output_private_subnet1_prefix"></a> [private\_subnet1\_prefix](#output\_private\_subnet1\_prefix) | CIDRs |
| <a name="output_private_subnet2_prefix"></a> [private\_subnet2\_prefix](#output\_private\_subnet2\_prefix) | n/a |
| <a name="output_public_subnet1_prefix"></a> [public\_subnet1\_prefix](#output\_public\_subnet1\_prefix) | n/a |
| <a name="output_public_subnet2_prefix"></a> [public\_subnet2\_prefix](#output\_public\_subnet2\_prefix) | n/a |
| <a name="output_resource_group_location"></a> [resource\_group\_location](#output\_resource\_group\_location) | The Azure region where the Martini resources are deployed. |
| <a name="output_resource_group_name"></a> [resource\_group\_name](#output\_resource\_group\_name) | Name of the resource group created for the application |
<!-- END_TF_DOCS -->