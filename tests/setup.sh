#!/bin/bash
# Ensure a working kubeconfig exists at tests/.kubeconfig.
#
# Behaviour:
#   - If tests/.kubeconfig already exists (CI/CD or pre-provisioned cluster),
#     print its path and exit — no cluster is created.
#   - Otherwise, create a local k3d cluster named arrmada-test and write the
#     kubeconfig to tests/.kubeconfig.
#
# This means the same `make setup` call works both in CI (where the runner
# pre-creates tests/.kubeconfig via a kubeconfig secret/step) and locally
# (where k3d is used for a throwaway cluster).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBECONFIG_FILE="${SCRIPT_DIR}/.kubeconfig"
K3D_CLUSTER="arrmada-test"

if [[ -f "${KUBECONFIG_FILE}" ]]; then
  echo "Kubeconfig already exists at ${KUBECONFIG_FILE} — skipping k3d cluster creation."
  exit 0
fi

echo "No kubeconfig found at ${KUBECONFIG_FILE}; creating k3d cluster '${K3D_CLUSTER}'..."
k3d cluster create --config "${SCRIPT_DIR}/k3d-cluster.yaml"
k3d kubeconfig get "${K3D_CLUSTER}" > "${KUBECONFIG_FILE}"
echo "Kubeconfig written to ${KUBECONFIG_FILE}."
