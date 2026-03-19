#!/bin/bash
# Delete the k3d test cluster and remove the kubeconfig.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBECONFIG_FILE="${SCRIPT_DIR}/.kubeconfig.yml"
K3D_CLUSTER="arrmada-test"

echo "Deleting k3d cluster '${K3D_CLUSTER}'..."
k3d cluster delete "${K3D_CLUSTER}"

if [[ -f "${KUBECONFIG_FILE}" ]]; then
  rm -f "${KUBECONFIG_FILE}"
  echo "Removed ${KUBECONFIG_FILE}"
fi

echo "Done."
