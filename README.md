<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | ~> 4.37.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | 4.37.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_app_gw"></a> [app\_gw](#module\_app\_gw) | Azure/avm-res-network-applicationgateway/azurerm | ~> 0.4.2 |
| <a name="module_nat_gw"></a> [nat\_gw](#module\_nat\_gw) | Azure/avm-res-network-natgateway/azurerm | ~> 0.2.1 |
| <a name="module_network_sg"></a> [network\_sg](#module\_network\_sg) | Azure/avm-res-network-networksecuritygroup/azurerm | ~> 0.5.0 |
| <a name="module_route_table"></a> [route\_table](#module\_route\_table) | Azure/avm-res-network-routetable/azurerm | ~> 0.4.1 |
| <a name="module_virtual_network"></a> [virtual\_network](#module\_virtual\_network) | Azure/avm-res-network-virtualnetwork/azurerm | ~> 0.9.3 |

## Resources

| Name | Type |
|------|------|
| [azurerm_container_group.martini](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/container_group) | resource |
| [azurerm_key_vault.key_vault](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault) | resource |
| [azurerm_key_vault_secret.martini_workspace_license](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_secret) | resource |
| [azurerm_public_ip.app_gw_pip](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/public_ip) | resource |
| [azurerm_resource_group.rg](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group) | resource |
| [azurerm_client_config.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_aci_docker_image_url"></a> [aci\_docker\_image\_url](#input\_aci\_docker\_image\_url) | A URL to the Docker image used by the application | `string` | `"lontiplatform/martini-server-runtime:latest"` | no |
| <a name="input_cpu"></a> [cpu](#input\_cpu) | Number of CPU cores to allocate for the application. | `number` | `2` | no |
| <a name="input_martini_workspace_license"></a> [martini\_workspace\_license](#input\_martini\_workspace\_license) | Full license text to be used with Martini | `string` | n/a | yes |
| <a name="input_martini_workspace_mysql_driver_version"></a> [martini\_workspace\_mysql\_driver\_version](#input\_martini\_workspace\_mysql\_driver\_version) | Version of the MySQL driver that should be automatically installed on Martini | `string` | `"8.3.0"` | no |
| <a name="input_martini_workspace_postgres_driver_version"></a> [martini\_workspace\_postgres\_driver\_version](#input\_martini\_workspace\_postgres\_driver\_version) | Version of the PostgreSQL driver that should be automatically installed on Martini | `string` | `"42.7.1"` | no |
| <a name="input_memory"></a> [memory](#input\_memory) | Amount of memory (in GB) to allocate for the application | `number` | `4` | no |
| <a name="input_name_suffix"></a> [name\_suffix](#input\_name\_suffix) | Suffix to add to the resources' names | `string` | `""` | no |
| <a name="input_rg_location"></a> [rg\_location](#input\_rg\_location) | Azure region to deploy resources into | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Common tags for components created in the infrastructure | `map(string)` | <pre>{<br/>  "Application": "Martini",<br/>  "Repository": "https://github.com/lontiplatform/martini-azure-terraform-template"<br/>}</pre> | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_app_gw_url"></a> [app\_gw\_url](#output\_app\_gw\_url) | n/a |
| <a name="output_resource_group_location"></a> [resource\_group\_location](#output\_resource\_group\_location) | n/a |
| <a name="output_resource_group_name"></a> [resource\_group\_name](#output\_resource\_group\_name) | n/a |
<!-- END_TF_DOCS -->