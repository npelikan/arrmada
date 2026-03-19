#!/bin/bash
# Delete the local k3d test cluster and remove the kubeconfig.
# Only meaningful in local-dev mode; in CI the cluster is managed externally.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBECONFIG_FILE="${SCRIPT_DIR}/.kubeconfig"
K3D_CLUSTER="arrmada-test"

echo "Deleting k3d cluster '${K3D_CLUSTER}'..."
k3d cluster delete "${K3D_CLUSTER}"

if [[ -f "${KUBECONFIG_FILE}" ]]; then
  rm -f "${KUBECONFIG_FILE}"
  echo "Removed ${KUBECONFIG_FILE}."
fi

echo "Done."
