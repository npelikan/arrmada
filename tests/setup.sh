#!/bin/bash
# Create the k3d test cluster and write the kubeconfig to tests/.kubeconfig.yml.
# Safe to run multiple times — skips creation if cluster already exists.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBECONFIG_FILE="${SCRIPT_DIR}/.kubeconfig.yml"
K3D_CLUSTER="arrmada-test"

if ! k3d cluster list 2>/dev/null | grep -q "${K3D_CLUSTER}"; then
  echo "Creating k3d cluster '${K3D_CLUSTER}'..."
  k3d cluster create --config "${SCRIPT_DIR}/k3d-cluster.yaml"
else
  echo "Cluster '${K3D_CLUSTER}' already exists, skipping creation."
fi

echo "Writing kubeconfig to ${KUBECONFIG_FILE}..."
k3d kubeconfig get "${K3D_CLUSTER}" > "${KUBECONFIG_FILE}"
echo "Done. Export KUBECONFIG=${KUBECONFIG_FILE} to use it."
