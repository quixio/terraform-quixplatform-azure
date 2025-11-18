<!-- BEGIN_TF_DOCS -->
## Requirements

| Name                                                                      | Version             |
| ------------------------------------------------------------------------- | ------------------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.0            |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm)       | >= 3.112.0, < 4.0.0 |

## Providers

| Name                                                          | Version             |
| ------------------------------------------------------------- | ------------------- |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | >= 3.112.0, < 4.0.0 |

## Modules

No modules.

## Resources

| Name                                                                                                                                                                                | Type     |
| ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- |
| [azurerm_private_dns_zone.storage_file](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_zone)                                           | resource |
| [azurerm_private_dns_zone_virtual_network_link.storage_file](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_zone_virtual_network_link) | resource |
| [azurerm_private_endpoint.nfs](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_endpoint)                                                    | resource |
| [azurerm_storage_account.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_account)                                                     | resource |
| [azurerm_storage_account_network_rules.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_account_network_rules)                         | resource |
| [azurerm_storage_share.nfs_shares](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_share)                                                   | resource |

## Inputs

| Name                                                                                                                   | Description                                                                                                                                        | Type                                                                                                                                                                            | Default                                  | Required |
| ---------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------- | :------: |
| <a name="input_allowed_ip_addresses"></a> [allowed\_ip\_addresses](#input\_allowed\_ip\_addresses)                     | List of IP addresses or CIDR ranges that are allowed to access the storage account (e.g., admin IP for Terraform operations to create file shares) | `list(string)`                                                                                                                                                                  | `[]`                                     |    no    |
| <a name="input_allowed_subnet_ids"></a> [allowed\_subnet\_ids](#input\_allowed\_subnet\_ids)                           | List of subnet IDs that are allowed to access the storage account (e.g., AKS nodes subnet for NFS access)                                          | `list(string)`                                                                                                                                                                  | `[]`                                     |    no    |
| <a name="input_location"></a> [location](#input\_location)                                                             | Azure region                                                                                                                                       | `string`                                                                                                                                                                        | n/a                                      |   yes    |
| <a name="input_network_bypass"></a> [network\_bypass](#input\_network\_bypass)                                         | List of services that can bypass network rules (AzureServices, Logging, Metrics, None)                                                             | `list(string)`                                                                                                                                                                  | <pre>[<br/>  "AzureServices"<br/>]</pre> |    no    |
| <a name="input_nfs_shares"></a> [nfs\_shares](#input\_nfs\_shares)                                                     | List of NFS file shares to create                                                                                                                  | <pre>list(object({<br/>    name        = string<br/>    quota_gb    = number<br/>    access_tier = optional(string)<br/>    metadata    = optional(map(string))<br/>  }))</pre> | `[]`                                     |    no    |
| <a name="input_private_dns_zone_ids"></a> [private\_dns\_zone\_ids](#input\_private\_dns\_zone\_ids)                   | List of Private DNS Zone IDs for privatelink.file.core.windows.net. If not provided, a new Private DNS Zone will be created automatically.         | `list(string)`                                                                                                                                                                  | `[]`                                     |    no    |
| <a name="input_private_endpoint_subnet_id"></a> [private\_endpoint\_subnet\_id](#input\_private\_endpoint\_subnet\_id) | Subnet ID where the Private Endpoint will be created (typically a dedicated subnet for private endpoints)                                          | `string`                                                                                                                                                                        | n/a                                      |   yes    |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name)                        | Resource group name (same RG as AKS)                                                                                                               | `string`                                                                                                                                                                        | n/a                                      |   yes    |
| <a name="input_storage_account_name"></a> [storage\_account\_name](#input\_storage\_account\_name)                     | Storage account name (must be globally unique, 3-24 chars, lowercase alphanumeric)                                                                 | `string`                                                                                                                                                                        | n/a                                      |   yes    |
| <a name="input_tags"></a> [tags](#input\_tags)                                                                         | Tags to apply to resources                                                                                                                         | `map(string)`                                                                                                                                                                   | `{}`                                     |    no    |
| <a name="input_vnet_id"></a> [vnet\_id](#input\_vnet\_id)                                                              | VNet ID to link the Private DNS Zone to (required if private\_dns\_zone\_ids is not provided)                                                      | `string`                                                                                                                                                                        | `null`                                   |    no    |

## Outputs

| Name                                                                                                                                                        | Description                                           |
| ----------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------- |
| <a name="output_nfs_shares"></a> [nfs\_shares](#output\_nfs\_shares)                                                                                        | Map of NFS mount paths for each share                 |
| <a name="output_private_dns_zone_id"></a> [private\_dns\_zone\_id](#output\_private\_dns\_zone\_id)                                                         | ID of the Private DNS Zone (auto-created or provided) |
| <a name="output_private_dns_zone_name"></a> [private\_dns\_zone\_name](#output\_private\_dns\_zone\_name)                                                   | Name of the Private DNS Zone                          |
| <a name="output_private_endpoint_id"></a> [private\_endpoint\_id](#output\_private\_endpoint\_id)                                                           | ID of the Private Endpoint                            |
| <a name="output_private_endpoint_ip_address"></a> [private\_endpoint\_ip\_address](#output\_private\_endpoint\_ip\_address)                                 | Private IP address of the Private Endpoint            |
| <a name="output_storage_account_id"></a> [storage\_account\_id](#output\_storage\_account\_id)                                                              | ID of the NFS storage account                         |
| <a name="output_storage_account_name"></a> [storage\_account\_name](#output\_storage\_account\_name)                                                        | Name of the NFS storage account                       |
| <a name="output_storage_account_primary_file_endpoint"></a> [storage\_account\_primary\_file\_endpoint](#output\_storage\_account\_primary\_file\_endpoint) | Primary file endpoint for NFS access                  |
| <a name="output_storage_account_primary_location"></a> [storage\_account\_primary\_location](#output\_storage\_account\_primary\_location)                  | Primary location of the NFS storage account           |
<!-- END_TF_DOCS -->