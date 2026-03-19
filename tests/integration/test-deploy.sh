#!/bin/bash
# Install (or upgrade) the arrmada chart into the test namespace.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="${SCRIPT_DIR}/.."
CHART_DIR="${TESTS_DIR}/.."

export KUBECONFIG="${TESTS_DIR}/.kubeconfig.yml"
NAMESPACE="arrmada-test"
RELEASE="arrmada-test"

echo "Installing/upgrading chart release '${RELEASE}' in namespace '${NAMESPACE}'..."
helm upgrade --install "${RELEASE}" "${CHART_DIR}" \
  --kubeconfig "${KUBECONFIG}" \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  -f "${TESTS_DIR}/values-test.yaml" \
  --wait \
  --timeout 300s

echo "Waiting for all pods to be ready..."
kubectl rollout status deployment \
  --kubeconfig "${KUBECONFIG}" \
  -n "${NAMESPACE}" \
  --timeout=300s \
  "${RELEASE}-sonarr" "${RELEASE}-radarr" "${RELEASE}-prowlarr"

echo "Chart deployed successfully."
