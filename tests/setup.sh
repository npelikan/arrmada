#!/bin/bash
# Ensure a working kubeconfig exists at tests/.kubeconfig.
#
# Behaviour:
#   - If tests/.kubeconfig exists AND the cluster is reachable, use it as-is.
#     This covers CI (runner writes the kubeconfig before calling make) and
#     local dev with an already-running cluster.
#   - If tests/.kubeconfig exists but the cluster is NOT reachable (e.g. the
#     cluster was manually deleted while the file remained), exit with an error
#     explaining how to recover.  Do not silently overwrite the file, because
#     in CI the kubeconfig came from a secret and we should not mask the real
#     problem.
#   - If tests/.kubeconfig does not exist, create a local k3d cluster and
#     write the kubeconfig there (local dev default path).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBECONFIG_FILE="${SCRIPT_DIR}/.kubeconfig"
K3D_CLUSTER="arrmada-test"

if [[ -f "${KUBECONFIG_FILE}" ]]; then
  if KUBECONFIG="${KUBECONFIG_FILE}" kubectl cluster-info > /dev/null 2>&1; then
    echo "Kubeconfig exists and cluster is reachable — skipping k3d cluster creation."
    exit 0
  else
    echo "ERROR: tests/.kubeconfig exists but the cluster is not reachable." >&2
    echo "       If you manually deleted the cluster, run 'make teardown' to" >&2
    echo "       remove the stale file, then retry." >&2
    exit 1
  fi
fi

echo "No kubeconfig found at ${KUBECONFIG_FILE}; creating k3d cluster '${K3D_CLUSTER}'..."
k3d cluster create --config "${SCRIPT_DIR}/k3d-cluster.yaml"
k3d kubeconfig get "${K3D_CLUSTER}" > "${KUBECONFIG_FILE}"
echo "Kubeconfig written to ${KUBECONFIG_FILE}."
