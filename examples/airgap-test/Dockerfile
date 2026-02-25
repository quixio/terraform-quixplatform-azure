# Airgap Test Runner Container
#
# Complete toolchain for running airgap tests:
# - Terraform (infrastructure provisioning)
# - Azure CLI (Azure operations)
# - kubectl (Kubernetes operations)
# - Helm (chart operations)
#
# Note: Ansible runs inside the K8s cluster via Jobs deployed by Helm,
# not on this machine.
#
# Build:
#   docker build --platform linux/amd64 -t $ACR_REGISTRY/airgap-test-runner:latest .
#
# Push (after az acr login -n $ACR_NAME):
#   docker push $ACR_REGISTRY/airgap-test-runner:latest
#
# Run (interactive):
#   docker run -it --rm \
#     -v ~/.azure:/root/.azure \
#     -v ~/.kube:/root/.kube \
#     -v $(pwd):/workspace \
#     -w /workspace \
#     -e QUIX_ACR_USERNAME -e QUIX_ACR_PASSWORD \
#     -e ACR_REGISTRY -e ACR_ID \
#     -e QUIX_LICENSE_KEY \
#     $ACR_REGISTRY/airgap-test-runner:latest ./run-airgap-test.sh
#
# For Azure DevOps:
#   container: $ACR_REGISTRY/airgap-test-runner:latest
#   Mount credentials via pipeline variables

FROM mcr.microsoft.com/azure-cli:cbl-mariner2.0

# Tool versions - pinned for reproducibility
ARG TERRAFORM_VERSION=1.7.5
ARG KUBECTL_VERSION=1.33.0
ARG HELM_VERSION=3.14.0

# Install base packages
# shadow-utils: provides su/useradd (required by Azure DevOps container job init)
# sudo: required by Azure DevOps to grant pipeline user permissions
RUN tdnf install -y \
    unzip \
    curl \
    tar \
    gzip \
    git \
    jq \
    gawk \
    diffutils \
    ca-certificates \
    shadow-utils \
    sudo \
    util-linux \
    && tdnf clean all

# Install yq (YAML processor - required by dev.sh)
RUN curl -fsSL "https://github.com/mikefarah/yq/releases/download/v4.40.5/yq_linux_amd64" -o /usr/local/bin/yq \
    && chmod +x /usr/local/bin/yq

# Install Terraform
RUN curl -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" -o /tmp/terraform.zip \
    && unzip /tmp/terraform.zip -d /usr/local/bin \
    && rm /tmp/terraform.zip \
    && chmod +x /usr/local/bin/terraform

# Install kubectl
RUN curl -fsSL "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl" -o /usr/local/bin/kubectl \
    && chmod +x /usr/local/bin/kubectl

# Install Helm
RUN curl -fsSL "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz" -o /tmp/helm.tar.gz \
    && tar -xzf /tmp/helm.tar.gz -C /tmp \
    && mv /tmp/linux-amd64/helm /usr/local/bin/helm \
    && rm -rf /tmp/helm.tar.gz /tmp/linux-amd64 \
    && chmod +x /usr/local/bin/helm

# Create workspace directory
WORKDIR /workspace

# Verify all tools are installed
RUN echo "=== Tool Versions ===" \
    && az version --output table \
    && terraform version \
    && kubectl version --client \
    && helm version --short \
    && echo "=== All tools installed successfully ==="

# Set bash as default shell for better script compatibility
SHELL ["/bin/bash", "-c"]

# Azure DevOps container jobs expect /home/vsts to exist as the working directory
RUN mkdir -p /home/vsts && chmod 777 /home/vsts

# No ENTRYPOINT/CMD - Azure DevOps manages the container lifecycle for container jobs.
# For local use, run with: docker run -it ... /bin/bash
