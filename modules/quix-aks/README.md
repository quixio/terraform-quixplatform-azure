<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 3.112.0, < 4.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | 3.117.1 |
| <a name="provider_null"></a> [null](#provider\_null) | 3.2.4 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [azurerm_bastion_host.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/bastion_host) | resource |
| [azurerm_kubernetes_cluster.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kubernetes_cluster) | resource |
| [azurerm_kubernetes_cluster_node_pool.additional](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kubernetes_cluster_node_pool) | resource |
| [azurerm_linux_virtual_machine.jumpbox](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/linux_virtual_machine) | resource |
| [azurerm_nat_gateway.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/nat_gateway) | resource |
| [azurerm_nat_gateway_public_ip_association.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/nat_gateway_public_ip_association) | resource |
| [azurerm_network_interface.jumpbox](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_interface) | resource |
| [azurerm_public_ip.bastion](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/public_ip) | resource |
| [azurerm_public_ip.nat_gateway](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/public_ip) | resource |
| [azurerm_resource_group.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group) | resource |
| [azurerm_role_assignment.aks_nodes_subnet](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.aks_rg](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.aks_vnet](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_subnet.bastion](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet) | resource |
| [azurerm_subnet.nodes](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet) | resource |
| [azurerm_subnet_nat_gateway_association.nodes](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet_nat_gateway_association) | resource |
| [azurerm_user_assigned_identity.nat_identity](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/user_assigned_identity) | resource |
| [azurerm_virtual_network.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_network) | resource |
| [null_resource.aks_credentials](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [azurerm_resource_group.existing](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/resource_group) | data source |
| [azurerm_role_definition.contributor](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/role_definition) | data source |
| [azurerm_role_definition.network_contributor](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/role_definition) | data source |
| [azurerm_subnet.bastion](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/subnet) | data source |
| [azurerm_subnet.nodes](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/subnet) | data source |
| [azurerm_virtual_network.existing](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/virtual_network) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_attach_identity_ids"></a> [attach\_identity\_ids](#input\_attach\_identity\_ids) | Additional user-assigned identity IDs to attach to the cluster | `list(string)` | `[]` | no |
| <a name="input_availability_zone"></a> [availability\_zone](#input\_availability\_zone) | Availability zone for public IP | `string` | n/a | yes |
| <a name="input_bastion_name"></a> [bastion\_name](#input\_bastion\_name) | Name of the Azure Bastion resource | `string` | `"QuixBastion"` | no |
| <a name="input_bastion_public_ip_id"></a> [bastion\_public\_ip\_id](#input\_bastion\_public\_ip\_id) | Existing Bastion Public IP ID to reuse (skip public IP creation when set) | `string` | `null` | no |
| <a name="input_bastion_public_ip_name"></a> [bastion\_public\_ip\_name](#input\_bastion\_public\_ip\_name) | Name of the Public IP for Azure Bastion | `string` | `"QuixBastionIP"` | no |
| <a name="input_bastion_subnet_cidr"></a> [bastion\_subnet\_cidr](#input\_bastion\_subnet\_cidr) | CIDR for AzureBastionSubnet | `string` | `"10.0.64.0/27"` | no |
| <a name="input_bastion_subnet_id"></a> [bastion\_subnet\_id](#input\_bastion\_subnet\_id) | Existing AzureBastionSubnet ID to reuse (skip subnet creation when set) | `string` | `null` | no |
| <a name="input_create_bastion_subnet"></a> [create\_bastion\_subnet](#input\_create\_bastion\_subnet) | Whether to create AzureBastionSubnet (set false when supplying bastion\_subnet\_id) | `bool` | `true` | no |
| <a name="input_create_nat"></a> [create\_nat](#input\_create\_nat) | Whether to create NAT Gateway and its Public IP (set false to bring your own) | `bool` | `true` | no |
| <a name="input_create_nodes_subnet"></a> [create\_nodes\_subnet](#input\_create\_nodes\_subnet) | Whether to create the nodes subnet (set false when using external nodes\_subnet\_id) | `bool` | `true` | no |
| <a name="input_create_resource_group"></a> [create\_resource\_group](#input\_create\_resource\_group) | Whether to create the resource group | `bool` | `true` | no |
| <a name="input_create_vnet"></a> [create\_vnet](#input\_create\_vnet) | Whether to create the VNet (set false when using external vnet\_id) | `bool` | `true` | no |
| <a name="input_enable_bastion"></a> [enable\_bastion](#input\_enable\_bastion) | Deploy Azure Bastion and its required subnet | `bool` | `false` | no |
| <a name="input_enable_credentials_fetch"></a> [enable\_credentials\_fetch](#input\_enable\_credentials\_fetch) | Run az aks get-credentials after creating the cluster | `bool` | `false` | no |
| <a name="input_jumpbox_admin_username"></a> [jumpbox\_admin\_username](#input\_jumpbox\_admin\_username) | Admin username for the jumpbox | `string` | `"azureuser"` | no |
| <a name="input_jumpbox_name"></a> [jumpbox\_name](#input\_jumpbox\_name) | Name of the jumpbox VM | `string` | `"quix-jumpbox"` | no |
| <a name="input_jumpbox_ssh_public_key"></a> [jumpbox\_ssh\_public\_key](#input\_jumpbox\_ssh\_public\_key) | SSH public key for the jumpbox admin user | `string` | `""` | no |
| <a name="input_jumpbox_vm_size"></a> [jumpbox\_vm\_size](#input\_jumpbox\_vm\_size) | VM size for the jumpbox | `string` | `"Standard_B2s"` | no |
| <a name="input_kubernetes_version"></a> [kubernetes\_version](#input\_kubernetes\_version) | Kubernetes version | `string` | n/a | yes |
| <a name="input_location"></a> [location](#input\_location) | Azure region | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Name of the AKS cluster | `string` | n/a | yes |
| <a name="input_nat_gateway_id"></a> [nat\_gateway\_id](#input\_nat\_gateway\_id) | Existing NAT Gateway ID to associate when create\_nat is false | `string` | `null` | no |
| <a name="input_nat_gateway_name"></a> [nat\_gateway\_name](#input\_nat\_gateway\_name) | Name of the NAT Gateway | `string` | n/a | yes |
| <a name="input_nat_identity_name"></a> [nat\_identity\_name](#input\_nat\_identity\_name) | Name of the managed identity for NAT | `string` | n/a | yes |
| <a name="input_network_profile"></a> [network\_profile](#input\_network\_profile) | AKS network profile | <pre>object({<br/>    network_plugin_mode = string # "overlay" or "vnet"<br/>    service_cidr        = string<br/>    dns_service_ip      = string<br/>    pod_cidr            = optional(string)<br/>    network_policy      = optional(string, "calico")<br/>    outbound_type       = optional(string, "userAssignedNATGateway")<br/>  })</pre> | n/a | yes |
| <a name="input_node_pools"></a> [node\_pools](#input\_node\_pools) | Map of additional node pools (include a 'system' pool to override default) | <pre>map(object({<br/>    name       = string<br/>    type       = string # system | user<br/>    node_count = number<br/>    vm_size    = string<br/>    max_pods   = optional(number)<br/>    taints     = optional(list(string))<br/>    labels     = optional(map(string))<br/>    mode       = optional(string) # system | user (overrides type)<br/>  }))</pre> | `{}` | no |
| <a name="input_nodes_subnet_cidr"></a> [nodes\_subnet\_cidr](#input\_nodes\_subnet\_cidr) | CIDR for the AKS nodes subnet | `string` | n/a | yes |
| <a name="input_nodes_subnet_id"></a> [nodes\_subnet\_id](#input\_nodes\_subnet\_id) | Existing nodes subnet ID to reuse (skip subnet creation when set) | `string` | `null` | no |
| <a name="input_nodes_subnet_name"></a> [nodes\_subnet\_name](#input\_nodes\_subnet\_name) | Name of the AKS nodes subnet | `string` | n/a | yes |
| <a name="input_oidc_issuer_enabled"></a> [oidc\_issuer\_enabled](#input\_oidc\_issuer\_enabled) | Enable OIDC issuer | `bool` | `true` | no |
| <a name="input_private_cluster_enabled"></a> [private\_cluster\_enabled](#input\_private\_cluster\_enabled) | Enable AKS private cluster | `bool` | `false` | no |
| <a name="input_public_ip_name"></a> [public\_ip\_name](#input\_public\_ip\_name) | Name of the public IP for NAT Gateway | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Resource group name (existing or to be created) | `string` | n/a | yes |
| <a name="input_sku_tier"></a> [sku\_tier](#input\_sku\_tier) | AKS tier (Free or Standard) | `string` | `"Standard"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to resources | `map(string)` | `{}` | no |
| <a name="input_vnet_address_space"></a> [vnet\_address\_space](#input\_vnet\_address\_space) | Address space for the Virtual Network | `list(string)` | n/a | yes |
| <a name="input_vnet_id"></a> [vnet\_id](#input\_vnet\_id) | Existing VNet ID to reuse (skip VNet creation when set) | `string` | `null` | no |
| <a name="input_vnet_name"></a> [vnet\_name](#input\_vnet\_name) | Name of the Virtual Network | `string` | n/a | yes |
| <a name="input_workload_identity_enabled"></a> [workload\_identity\_enabled](#input\_workload\_identity\_enabled) | Enable workload identity | `bool` | `true` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_aks_id"></a> [aks\_id](#output\_aks\_id) | ID of the AKS cluster |
| <a name="output_cluster_identity_client_id"></a> [cluster\_identity\_client\_id](#output\_cluster\_identity\_client\_id) | Client ID of the cluster's user-assigned identity |
| <a name="output_cluster_identity_principal_id"></a> [cluster\_identity\_principal\_id](#output\_cluster\_identity\_principal\_id) | Principal ID of the cluster's user-assigned identity |
| <a name="output_cluster_identity_resource_id"></a> [cluster\_identity\_resource\_id](#output\_cluster\_identity\_resource\_id) | Resource ID of the cluster's user-assigned identity |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | AKS cluster name |
| <a name="output_fqdn"></a> [fqdn](#output\_fqdn) | Public FQDN of the API server (null if private) |
| <a name="output_kubelet_identity_client_id"></a> [kubelet\_identity\_client\_id](#output\_kubelet\_identity\_client\_id) | Kubelet identity client ID |
| <a name="output_kubelet_identity_object_id"></a> [kubelet\_identity\_object\_id](#output\_kubelet\_identity\_object\_id) | Kubelet identity object ID |
| <a name="output_kubelet_identity_resource_id"></a> [kubelet\_identity\_resource\_id](#output\_kubelet\_identity\_resource\_id) | Kubelet identity resource ID |
| <a name="output_nat_gateway_public_ip"></a> [nat\_gateway\_public\_ip](#output\_nat\_gateway\_public\_ip) | Public IP address of the NAT Gateway |
| <a name="output_node_resource_group"></a> [node\_resource\_group](#output\_node\_resource\_group) | Node resource group name |
| <a name="output_nodes_subnet_id"></a> [nodes\_subnet\_id](#output\_nodes\_subnet\_id) | ID of the nodes subnet |
| <a name="output_nodes_subnet_name"></a> [nodes\_subnet\_name](#output\_nodes\_subnet\_name) | Name of the nodes subnet |
| <a name="output_oidc_issuer_url"></a> [oidc\_issuer\_url](#output\_oidc\_issuer\_url) | OIDC issuer URL (null if disabled) |
| <a name="output_private_fqdn"></a> [private\_fqdn](#output\_private\_fqdn) | Private FQDN of the API server (null if public) |
| <a name="output_resource_group_id"></a> [resource\_group\_id](#output\_resource\_group\_id) | ID of the resource group |
| <a name="output_resource_group_location"></a> [resource\_group\_location](#output\_resource\_group\_location) | Location of the resource group |
| <a name="output_resource_group_name"></a> [resource\_group\_name](#output\_resource\_group\_name) | Name of the resource group |
| <a name="output_vnet_id"></a> [vnet\_id](#output\_vnet\_id) | ID of the virtual network |
<!-- END_TF_DOCS -->
