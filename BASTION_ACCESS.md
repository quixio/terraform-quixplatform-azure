# Accessing Private AKS via Azure Bastion

This guide shows how to connect to a private AKS cluster using Azure Bastion, either by running kubectl from the jumpbox VM or from your local machine using Bastion tunneling.

## Prerequisites

- Azure Bastion (Standard SKU) deployed (enable_bastion = true)
- Jumpbox VM created (auto-created when Bastion is enabled)
- Azure CLI installed locally
- Your SSH private key corresponding to jumpbox_ssh_public_key

## Option A: Run kubectl from the Jumpbox

1. Open an SSH session to the jumpbox via Bastion (Native client):
```bash
export RG="<RESOURCE_GROUP>"
export BASTION="<BASTION_NAME>"
export VM="<JUMPBOX_NAME>"
export SSH_KEY="$HOME/.ssh/id_rsa"

VM_ID=$(az vm show -g "$RG" -n "$VM" --query id -o tsv)
az network bastion ssh \
  --name "$BASTION" \
  --resource-group "$RG" \
  --target-resource-id "$VM_ID" \
  --auth-type ssh-key --username <ADMIN_USERNAME> --ssh-key $SSH_KEY
```

2. Inside the VM, authenticate and fetch kubeconfig:
```bash
az login --use-device-code
az account set --subscription "<SUBSCRIPTION_ID>"
az aks get-credentials -g "<RESOURCE_GROUP>" -n "<AKS_NAME>" --overwrite-existing
kubectl get nodes -o wide
```

## Option B: Run kubectl from your local machine (Bastion tunneling)

1. Start SSH tunnel to the VM via Bastion:
```bash
export RG="<RESOURCE_GROUP>"
export BASTION="<BASTION_NAME>"
export VM="<JUMPBOX_NAME>"
export SSH_KEY="$HOME/.ssh/id_rsa"

VM_ID=$(az vm show -g "$RG" -n "$VM" --query id -o tsv)
az network bastion tunnel \
  --name "$BASTION" \
  --resource-group "$RG" \
  --target-resource-id "$VM_ID" \
  --resource-port 22 --port 2222
```
Keep this terminal open.

2. In a second terminal, forward the AKS API through the VM:
```bash
export RG="<RESOURCE_GROUP>"
export AKS="<AKS_NAME>"
export SSH_KEY="$HOME/.ssh/id_rsa"
export ADMIN_USERNAME="<ADMIN_USERNAME>"
PRIVATE_FQDN=$(az aks show -g "$RG" -n "$AKS" --query privateFqdn -o tsv)
ssh -p 2222 -i "$SSH_KEY" $ADMIN_USERNAME@127.0.0.1 -L 6443:${PRIVATE_FQDN}:443 -N
```
Keep this terminal open.

3. Get AKS credentials and point kubeconfig to the local tunnel (requires jq: `brew install jq`):
```bash
az aks get-credentials -g "$RG" -n "$AKS" --overwrite-existing --context "${AKS}-bastion"

# Get the cluster entry name for this context
CLUSTER_NAME=$(kubectl config view --raw -o json | jq -r --arg ctx "${AKS}-bastion" '.contexts[] | select(.name==$ctx) | .context.cluster')

# Resolve private FQDN and point kubeconfig to the local tunnel with proper TLS SNI
PRIVATE_FQDN=$(az aks show -g "$RG" -n "$AKS" --query privateFqdn -o tsv)
kubectl config set-cluster "$CLUSTER_NAME" --server="https://127.0.0.1:6443"
kubectl config set-cluster "$CLUSTER_NAME" --tls-server-name="$PRIVATE_FQDN"
```

4. Use kubectl locally:
```bash
kubectl --context "${AKS}-bastion" get nodes -o wide
```

## Notes
- Bastion must be Standard or Premium SKU, with tunneling enabled.
- The jumpbox VM resides in the nodes subnet; do not place VMs inside AzureBastionSubnet.
- Alternatively, you can execute ad-hoc commands without tunnels using:
```bash
az aks command invoke -g <RESOURCE_GROUP> -n <AKS_NAME> --command "kubectl get nodes"
```

