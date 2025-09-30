# Terraform Modules (Azure)

Repository of production-ready Terraform modules. The primary module is `azure/modules/quix-aks` (full AKS with networking, NAT, RBAC, and optional Bastion/jumpbox).

## Structure

- `modules/quix-aks/` (AKS module)
  - `main.tf`: resource group wiring and common locals
  - `network.tf`: VNet, nodes subnet, NAT Gateway and identity
  - `aks.tf`: AKS cluster + dynamic node pools
  - `rbac.tf`: role assignments for the managed identity
  - `bastion.tf`: Azure Bastion + jumpbox (optional)
  - `README.md`: terraform-docs generated documentation
- `examples/` usage examples
  - `public-quix-infr/`: public cluster
  - `private-quix-infr/`: private cluster with Bastion + jumpbox
- `BASTION_ACCESS.md`: how to access a private AKS via Bastion

## AKS module (quix-aks)

Module documentation (inputs/outputs/resources):

- [modules/quix-aks/README.md](modules/quix-aks/README.md) (generated with terraform-docs)

Regenerate docs (requires `terraform-docs`):

```bash
cd modules/quix-aks
terraform-docs markdown table --output-file README.md --output-mode inject .
```

## Examples

Public example:

```bash
cd examples/public-quix-infr
terraform init
terraform apply
```

Private example (with Bastion):

```bash
cd examples/private-quix-infr
terraform init
terraform apply
```

Access a private AKS: see `BASTION_ACCESS.md`.

## Requirements

- Terraform >= 1.5.0
- AzureRM Provider >= 3.112.0, < 4.0.0
- Azure CLI

## Module versioning

Publish SemVer tags and reference the module with `?ref=vX.Y.Z` when consuming from git.
