#!/bin/bash
# Full integration test orchestrator.
# KUBECONFIG is inherited from the environment (set by the Makefile or the
# caller).  Falls back to tests/.kubeconfig relative to this script if unset.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="${SCRIPT_DIR}/.."

export KUBECONFIG="${KUBECONFIG:-${TESTS_DIR}/.kubeconfig}"
NAMESPACE="arrmada-test"

echo "Using KUBECONFIG=${KUBECONFIG}"
kubectl cluster-info > /dev/null

echo ""
echo "=== Phase 1: Deploy PostgreSQL fixture ==="
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n "${NAMESPACE}" -f "${TESTS_DIR}/fixtures/postgresql/"
echo "Waiting for PostgreSQL to be ready..."
kubectl rollout status deployment/postgresql -n "${NAMESPACE}" --timeout=120s

echo ""
echo "=== Phase 2: Install arrmada chart ==="
"${SCRIPT_DIR}/test-deploy.sh"

echo ""
echo "=== Phase 3: Verify services ==="
"${SCRIPT_DIR}/test-services.sh"

echo ""
echo "=== Phase 4: Verify config sync ==="
"${SCRIPT_DIR}/test-config-sync.sh"

echo ""
echo "=== Phase 5: Verify API state ==="
"${SCRIPT_DIR}/test-api-state.sh"

echo ""
echo "=== Phase 6: Verify Prowlarr application connections ==="
"${SCRIPT_DIR}/test-prowlarr-apps.sh"

echo ""
echo "=== All integration tests passed ==="
