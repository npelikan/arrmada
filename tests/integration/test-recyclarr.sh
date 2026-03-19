#!/bin/bash
# Trigger a one-off Recyclarr sync Job and verify it runs without error.
# Recyclarr is disabled by default in values-test.yaml; this test enables it
# by creating a temporary values override.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="${SCRIPT_DIR}/.."
CHART_DIR="${TESTS_DIR}/.."

export KUBECONFIG="${TESTS_DIR}/.kubeconfig.yml"
NAMESPACE="arrmada-test"
RELEASE="arrmada-test"

PASS=0
FAIL=0

echo "Upgrading chart with Recyclarr enabled (schedule: never automatic)..."
# Enable recyclarr with a placeholder schedule.
# We'll manually trigger a Job rather than waiting for the CronJob to fire.
helm upgrade "${RELEASE}" "${CHART_DIR}" \
  --kubeconfig "${KUBECONFIG}" \
  --namespace "${NAMESPACE}" \
  -f "${TESTS_DIR}/values-test.yaml" \
  --set recyclarr.enabled=true \
  --set recyclarr.schedule="0 0 31 2 *" \
  --wait \
  --timeout 120s

echo "Manually triggering Recyclarr CronJob..."
kubectl create job "${RELEASE}-recyclarr-manual" \
  --kubeconfig "${KUBECONFIG}" \
  -n "${NAMESPACE}" \
  --from="cronjob/${RELEASE}-recyclarr" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Waiting for manual Recyclarr Job to complete..."
if kubectl wait job "${RELEASE}-recyclarr-manual" \
  --kubeconfig "${KUBECONFIG}" \
  -n "${NAMESPACE}" \
  --for=condition=complete \
  --timeout=120s; then
  echo "  PASS: Recyclarr Job completed"
  PASS=$((PASS + 1))
else
  echo "  FAIL: Recyclarr Job did not complete in time"
  kubectl logs "job/${RELEASE}-recyclarr-manual" \
    --kubeconfig "${KUBECONFIG}" \
    -n "${NAMESPACE}" --tail=30 || true
  FAIL=$((FAIL + 1))
fi

# Cleanup
kubectl delete job "${RELEASE}-recyclarr-manual" \
  --kubeconfig "${KUBECONFIG}" \
  -n "${NAMESPACE}" \
  --ignore-not-found

echo ""
if [[ "${FAIL}" -gt 0 ]]; then
  echo "RESULT: ${PASS} passed, ${FAIL} failed"
  exit 1
fi
echo "RESULT: ${PASS} passed — Recyclarr Job ran successfully"
