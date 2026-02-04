# Airgap Test Runner Container
#
# Contains all tools needed to run the airgap test:
# - Terraform
# - Azure CLI
# - kubectl
# - Helm
#
# Build:
#   docker build -t airgap-test-runner .
#
# Run:
#   docker run -it --rm \
#     -v ~/.azure:/root/.azure \
#     -v $(pwd):/workspace \
#     -w /workspace \
#     airgap-test-runner
#
FROM mcr.microsoft.com/azure-cli:latest

# Install Terraform
ARG TERRAFORM_VERSION=1.7.0
RUN curl -fsSL https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip -o /tmp/terraform.zip && \
    unzip /tmp/terraform.zip -d /usr/local/bin && \
    rm /tmp/terraform.zip && \
    terraform version

# Install kubectl
RUN az aks install-cli

# Install Helm
RUN curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install jq and other utilities
RUN apk add --no-cache jq bash coreutils

# Verify installations
RUN az version && \
    terraform version && \
    kubectl version --client && \
    helm version

WORKDIR /workspace

# Default to bash
CMD ["/bin/bash"]
