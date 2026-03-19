#!/bin/bash
# Verify the config sync Job completed successfully.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="${SCRIPT_DIR}/.."

export KUBECONFIG="${TESTS_DIR}/.kubeconfig.yml"
NAMESPACE="arrmada-test"
RELEASE="arrmada-test"
JOB_NAME="${RELEASE}-config-sync"

PASS=0
FAIL=0

check() {
  local desc="$1"; shift
  if "$@"; then
    echo "  PASS: ${desc}"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: ${desc}"
    FAIL=$((FAIL + 1))
  fi
}

echo "Verifying config sync Job..."

# Wait for the Job to complete (it may still be running after helm install --wait)
echo "  Waiting for Job '${JOB_NAME}' to complete..."
kubectl wait job "${JOB_NAME}" \
  --kubeconfig "${KUBECONFIG}" \
  -n "${NAMESPACE}" \
  --for=condition=complete \
  --timeout=300s

check "config sync Job completed" kubectl get job "${JOB_NAME}" \
  --kubeconfig "${KUBECONFIG}" \
  -n "${NAMESPACE}" \
  -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' | grep -q "True"

# Verify the Job did not fail
failed=$(kubectl get job "${JOB_NAME}" \
  --kubeconfig "${KUBECONFIG}" \
  -n "${NAMESPACE}" \
  -o jsonpath='{.status.failed}' 2>/dev/null || echo "0")
if [[ "${failed}" == "0" ]] || [[ -z "${failed}" ]]; then
  echo "  PASS: config sync Job had no failed attempts"
  PASS=$((PASS + 1))
else
  echo "  FAIL: config sync Job had ${failed} failed attempt(s)"
  echo "  --- Job logs ---"
  kubectl logs job/"${JOB_NAME}" \
    --kubeconfig "${KUBECONFIG}" \
    -n "${NAMESPACE}" --tail=50 || true
  FAIL=$((FAIL + 1))
fi

echo ""
if [[ "${FAIL}" -gt 0 ]]; then
  echo "RESULT: ${PASS} passed, ${FAIL} failed"
  exit 1
fi
echo "RESULT: ${PASS} passed — config sync completed successfully"
