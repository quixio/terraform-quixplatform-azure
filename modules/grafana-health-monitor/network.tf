################################################################################
# Function App Subnet (only when private_grafana = true)
################################################################################

resource "azurerm_subnet" "function" {
  count = var.private_grafana && var.create_function_subnet ? 1 : 0

  name                 = "${var.name}-function-subnet"
  resource_group_name  = local.vnet_rg_name
  virtual_network_name = var.vnet_name
  address_prefixes     = [var.function_subnet_cidr]

  delegation {
    name = "function-delegation"

    service_delegation {
      name = "Microsoft.Web/serverFarms"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/action"
      ]
    }
  }
}

locals {
  # Only compute subnet ID when private_grafana is true
  function_subnet_id = var.private_grafana ? (
    var.create_function_subnet ? azurerm_subnet.function[0].id : var.function_subnet_id
  ) : null
}

################################################################################
# Validation (only applies when private_grafana = true)
################################################################################

check "subnet_configuration" {
  assert {
    condition     = !var.private_grafana || var.create_function_subnet || var.function_subnet_id != null
    error_message = "function_subnet_id is required when private_grafana is true and create_function_subnet is false."
  }

  assert {
    condition     = !var.private_grafana || !var.create_function_subnet || var.vnet_name != null
    error_message = "vnet_name is required when private_grafana is true and create_function_subnet is true."
  }
}
