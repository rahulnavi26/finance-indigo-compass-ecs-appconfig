#!/usr/bin/env bash
# Installs a pinned Terraform version. Usage: install-terraform.sh <version>
set -euo pipefail
V="$1"
curl -sSfLo /tmp/tf.zip \
  "https://releases.hashicorp.com/terraform/${V}/terraform_${V}_linux_amd64.zip"
unzip -oq /tmp/tf.zip -d /tmp/tf && sudo mv /tmp/tf/terraform /usr/local/bin/
terraform version
