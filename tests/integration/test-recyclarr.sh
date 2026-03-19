#!/bin/bash
# Integration tests for the Recyclarr integration.
# Covers: K8s resource creation, CronJob spec, ConfigMap content,
# job completion, log output, quality-definition sync effect on Sonarr/Radarr,
# PVC creation, and clean removal when disabled.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="${SCRIPT_DIR}/.."
CHART_DIR="${TESTS_DIR}/.."

export KUBECONFIG="${KUBECONFIG:-${TESTS_DIR}/.kubeconfig}"
NAMESPACE="arrmada-test"
RELEASE="arrmada-test"

PASS=0
FAIL=0

# Port-forward PIDs for cleanup
PF_PIDS=()

cleanup() {
  for pid in "${PF_PIDS[@]:-}"; do
    kill "${pid}" 2>/dev/null || true
    wait "${pid}" 2>/dev/null || true
  done
  # Delete manual jobs in case of early exit
  kubectl delete job "${RELEASE}-recyclarr-manual" \
    --kubeconfig "${KUBECONFIG}" -n "${NAMESPACE}" --ignore-not-found 2>/dev/null || true
  kubectl delete job "${RELEASE}-recyclarr-sync-manual" \
    --kubeconfig "${KUBECONFIG}" -n "${NAMESPACE}" --ignore-not-found 2>/dev/null || true
}
trap cleanup EXIT

check() {
  local desc="$1"; shift
  if "$@" 2>/dev/null; then
    echo "  PASS: ${desc}"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: ${desc}"
    FAIL=$((FAIL + 1))
  fi
}

check_contains() {
  local desc="$1" haystack="$2" needle="$3"
  if echo "${haystack}" | grep -qi "${needle}"; then
    echo "  PASS: ${desc}"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: ${desc} (expected '${needle}' in: ${haystack})"
    FAIL=$((FAIL + 1))
  fi
}

check_not_exists() {
  local desc="$1" resource="$2" name="$3"
  if kubectl get "${resource}" "${name}" \
    --kubeconfig "${KUBECONFIG}" -n "${NAMESPACE}" 2>&1 | grep -q "NotFound\|not found"; then
    echo "  PASS: ${desc}"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: ${desc} (resource still exists)"
    FAIL=$((FAIL + 1))
  fi
}

start_pf() {
  local svc="$1" port="$2" local_port="$3"
  kubectl port-forward \
    --kubeconfig "${KUBECONFIG}" \
    -n "${NAMESPACE}" \
    "svc/${RELEASE}-${svc}" "${local_port}:${port}" &
  PF_PIDS+=("$!")
}

get_api_key() {
  kubectl get secret "${RELEASE}-secrets" \
    --kubeconfig "${KUBECONFIG}" \
    -n "${NAMESPACE}" \
    -o "jsonpath={.data.$1}" | base64 -d
}

trigger_job() {
  local job_name="$1" cronjob_name="$2"
  kubectl create job "${job_name}" \
    --kubeconfig "${KUBECONFIG}" \
    -n "${NAMESPACE}" \
    --from="cronjob/${cronjob_name}" \
    --dry-run=client -o yaml | kubectl apply -f -
}

wait_for_job() {
  local job_name="$1" timeout="${2:-180s}"
  kubectl wait job "${job_name}" \
    --kubeconfig "${KUBECONFIG}" \
    -n "${NAMESPACE}" \
    --for=condition=complete \
    --timeout="${timeout}"
}

# ─── Phase 1: Verify Recyclarr resources absent before enabling ───────────────

echo "=== Phase 1: Verify Recyclarr resources absent (disabled) ==="

echo "Resetting chart to disabled-recyclarr baseline..."
helm upgrade "${RELEASE}" "${CHART_DIR}" \
  --kubeconfig "${KUBECONFIG}" \
  --namespace "${NAMESPACE}" \
  -f "${TESTS_DIR}/values-test.yaml" \
  --set recyclarr.enabled=false \
  --wait \
  --timeout 120s

# Helm's cascade deletion of CronJobs (which manage child Jobs) can take
# ~2 minutes for the GC cycle to process. Wait before asserting absence.
echo "Waiting for any previous recyclarr resources to be fully deleted..."
kubectl wait cronjob "${RELEASE}-recyclarr" \
  --kubeconfig "${KUBECONFIG}" -n "${NAMESPACE}" \
  --for=delete --timeout=180s 2>/dev/null || true
kubectl wait configmap "${RELEASE}-recyclarr-config" \
  --kubeconfig "${KUBECONFIG}" -n "${NAMESPACE}" \
  --for=delete --timeout=180s 2>/dev/null || true

check_not_exists "CronJob absent when Recyclarr disabled" \
  cronjob "${RELEASE}-recyclarr"
check_not_exists "ConfigMap absent when Recyclarr disabled" \
  configmap "${RELEASE}-recyclarr-config"

# ─── Phase 2: Enable Recyclarr and verify K8s resources ───────────────────────

echo ""
echo "=== Phase 2: Enable Recyclarr — verify K8s resources ==="

echo "Upgrading chart with Recyclarr enabled (unreachable schedule)..."
helm upgrade "${RELEASE}" "${CHART_DIR}" \
  --kubeconfig "${KUBECONFIG}" \
  --namespace "${NAMESPACE}" \
  -f "${TESTS_DIR}/values-test.yaml" \
  --set recyclarr.enabled=true \
  --set "recyclarr.schedule=0 0 31 2 *" \
  --wait \
  --timeout 120s

check "CronJob created when Recyclarr enabled" \
  kubectl get cronjob "${RELEASE}-recyclarr" \
    --kubeconfig "${KUBECONFIG}" -n "${NAMESPACE}"

schedule=$(kubectl get cronjob "${RELEASE}-recyclarr" \
  --kubeconfig "${KUBECONFIG}" -n "${NAMESPACE}" \
  -o jsonpath='{.spec.schedule}')
check "CronJob has configured schedule" \
  test "${schedule}" = "0 0 31 2 *"

concurrency=$(kubectl get cronjob "${RELEASE}-recyclarr" \
  --kubeconfig "${KUBECONFIG}" -n "${NAMESPACE}" \
  -o jsonpath='{.spec.concurrencyPolicy}')
check "CronJob concurrencyPolicy is Forbid" \
  test "${concurrency}" = "Forbid"

check "ConfigMap created when Recyclarr enabled" \
  kubectl get configmap "${RELEASE}-recyclarr-config" \
    --kubeconfig "${KUBECONFIG}" -n "${NAMESPACE}"

check "ConfigMap contains recyclarr.yml data key" \
  bash -c "kubectl get configmap '${RELEASE}-recyclarr-config' \
    --kubeconfig '${KUBECONFIG}' -n '${NAMESPACE}' \
    -o jsonpath='{.data}' | grep -q 'recyclarr\.yml'"

# ─── Phase 3: Basic job completion (no sync targets) ──────────────────────────

echo ""
echo "=== Phase 3: Basic job run (no sync targets configured) ==="

echo "Triggering manual Recyclarr Job..."
trigger_job "${RELEASE}-recyclarr-manual" "${RELEASE}-recyclarr"

echo "Waiting for Job to complete (180s)..."
if wait_for_job "${RELEASE}-recyclarr-manual"; then
  echo "  PASS: Recyclarr Job completed successfully"
  PASS=$((PASS + 1))
else
  echo "  FAIL: Recyclarr Job did not complete in time"
  kubectl logs "job/${RELEASE}-recyclarr-manual" \
    --kubeconfig "${KUBECONFIG}" -n "${NAMESPACE}" --tail=30 || true
  FAIL=$((FAIL + 1))
fi

failed=$(kubectl get job "${RELEASE}-recyclarr-manual" \
  --kubeconfig "${KUBECONFIG}" -n "${NAMESPACE}" \
  -o jsonpath='{.status.failed}' 2>/dev/null || echo "0")
check "Recyclarr Job had no failed attempts" \
  test "${failed:-0}" = "0"

logs=$(kubectl logs "job/${RELEASE}-recyclarr-manual" \
  --kubeconfig "${KUBECONFIG}" -n "${NAMESPACE}" 2>/dev/null || echo "")
# Recyclarr exits 0 even with no instances; verify absence of fatal errors
if echo "${logs}" | grep -qi "exception\|fatal"; then
  echo "  FAIL: Recyclarr logs contain exception or fatal error"
  echo "  --- logs ---"
  echo "${logs}" | tail -20
  FAIL=$((FAIL + 1))
else
  echo "  PASS: Recyclarr logs contain no exceptions or fatal errors"
  PASS=$((PASS + 1))
fi

kubectl delete job "${RELEASE}-recyclarr-manual" \
  --kubeconfig "${KUBECONFIG}" -n "${NAMESPACE}" --ignore-not-found

# ─── Phase 4: Quality definition sync effect on Sonarr and Radarr ─────────────

echo ""
echo "=== Phase 4: Quality definition sync — verify effect on Sonarr and Radarr ==="

echo "Upgrading chart with quality_definition configured for Sonarr and Radarr..."
helm upgrade "${RELEASE}" "${CHART_DIR}" \
  --kubeconfig "${KUBECONFIG}" \
  --namespace "${NAMESPACE}" \
  -f "${TESTS_DIR}/values-test.yaml" \
  --set recyclarr.enabled=true \
  --set "recyclarr.schedule=0 0 31 2 *" \
  --set recyclarr.config.sonarr.quality_definition.type=series \
  --set recyclarr.config.radarr.quality_definition.type=movie \
  --wait \
  --timeout 120s

echo "Triggering manual Recyclarr sync Job..."
trigger_job "${RELEASE}-recyclarr-sync-manual" "${RELEASE}-recyclarr"

echo "Waiting for quality-definition sync Job to complete (180s)..."
if wait_for_job "${RELEASE}-recyclarr-sync-manual"; then
  echo "  PASS: Recyclarr quality-definition sync Job completed"
  PASS=$((PASS + 1))
else
  echo "  FAIL: Recyclarr quality-definition sync Job did not complete"
  kubectl logs "job/${RELEASE}-recyclarr-sync-manual" \
    --kubeconfig "${KUBECONFIG}" -n "${NAMESPACE}" --tail=40 || true
  FAIL=$((FAIL + 1))
fi

sync_logs=$(kubectl logs "job/${RELEASE}-recyclarr-sync-manual" \
  --kubeconfig "${KUBECONFIG}" -n "${NAMESPACE}" 2>/dev/null || echo "")
check_contains "Recyclarr sync logs mention Sonarr instance" \
  "${sync_logs}" "sonarr"
check_contains "Recyclarr sync logs mention Radarr instance" \
  "${sync_logs}" "radarr"

echo "Verifying quality definitions updated in Sonarr..."
SONARR_KEY="$(get_api_key "sonarr-api-key")"
start_pf sonarr 8989 58989
sleep 3

sonarr_qdefs=$(curl -sf -H "X-Api-Key: ${SONARR_KEY}" \
  "http://localhost:58989/api/v3/qualitydefinition" 2>/dev/null || echo "[]")
check_contains "Sonarr quality definitions are non-empty after sync" \
  "${sonarr_qdefs}" "title"

# TRaSH series profile sets specific sizes — verify at least one definition has
# a non-zero minSize (default Sonarr minSize is 0 for many qualities)
non_zero=$(echo "${sonarr_qdefs}" | grep -c '"minSize":[^0]' || true)
check "Sonarr quality definitions have TRaSH-set min sizes" \
  test "${non_zero}" -gt 0

echo "Verifying quality definitions updated in Radarr..."
RADARR_KEY="$(get_api_key "radarr-api-key")"
start_pf radarr 7878 57878
sleep 3

radarr_qdefs=$(curl -sf -H "X-Api-Key: ${RADARR_KEY}" \
  "http://localhost:57878/api/v3/qualitydefinition" 2>/dev/null || echo "[]")
check_contains "Radarr quality definitions are non-empty after sync" \
  "${radarr_qdefs}" "title"

non_zero=$(echo "${radarr_qdefs}" | grep -c '"minSize":[^0]' || true)
check "Radarr quality definitions have TRaSH-set min sizes" \
  test "${non_zero}" -gt 0

kubectl delete job "${RELEASE}-recyclarr-sync-manual" \
  --kubeconfig "${KUBECONFIG}" -n "${NAMESPACE}" --ignore-not-found

# ─── Phase 5: PVC created when persistence enabled ────────────────────────────

echo ""
echo "=== Phase 5: PVC lifecycle ==="

echo "Upgrading chart with Recyclarr persistence enabled..."
# Do not pass --wait: with WaitForFirstConsumer storage classes (e.g. local-path
# in k3d/Rancher Desktop), the PVC stays Pending until a pod binds it. Helm's
# --wait would time out waiting for the PVC to become Bound.
helm upgrade "${RELEASE}" "${CHART_DIR}" \
  --kubeconfig "${KUBECONFIG}" \
  --namespace "${NAMESPACE}" \
  -f "${TESTS_DIR}/values-test.yaml" \
  --set recyclarr.enabled=true \
  --set "recyclarr.schedule=0 0 31 2 *" \
  --set recyclarr.persistence.enabled=true \
  --set recyclarr.persistence.size=1Gi \
  --timeout 120s
sleep 5  # give the API server a moment to create the PVC object

check "PVC created when recyclarr persistence enabled" \
  kubectl get pvc "${RELEASE}-recyclarr-cache" \
    --kubeconfig "${KUBECONFIG}" -n "${NAMESPACE}"

pvc_size=$(kubectl get pvc "${RELEASE}-recyclarr-cache" \
  --kubeconfig "${KUBECONFIG}" -n "${NAMESPACE}" \
  -o jsonpath='{.spec.resources.requests.storage}')
check "PVC has configured storage size" \
  test "${pvc_size}" = "1Gi"

echo "Disabling persistence — PVC should be retained (not deleted by Helm)..."
helm upgrade "${RELEASE}" "${CHART_DIR}" \
  --kubeconfig "${KUBECONFIG}" \
  --namespace "${NAMESPACE}" \
  -f "${TESTS_DIR}/values-test.yaml" \
  --set recyclarr.enabled=true \
  --set "recyclarr.schedule=0 0 31 2 *" \
  --set recyclarr.persistence.enabled=false \
  --wait \
  --timeout 120s

# The PVC has helm.sh/resource-policy: keep — Helm skips it during upgrade/delete
check "PVC is retained after persistence disabled (resource-policy: keep)" \
  kubectl get pvc "${RELEASE}-recyclarr-cache" \
    --kubeconfig "${KUBECONFIG}" -n "${NAMESPACE}"

# Manual cleanup for subsequent test runs
kubectl delete pvc "${RELEASE}-recyclarr-cache" \
  --kubeconfig "${KUBECONFIG}" -n "${NAMESPACE}" --ignore-not-found

# ─── Phase 6: Disable Recyclarr — verify resources removed ───────────────────

echo ""
echo "=== Phase 6: Disable Recyclarr — verify K8s resources removed ==="

echo "Upgrading chart with Recyclarr disabled..."
helm upgrade "${RELEASE}" "${CHART_DIR}" \
  --kubeconfig "${KUBECONFIG}" \
  --namespace "${NAMESPACE}" \
  -f "${TESTS_DIR}/values-test.yaml" \
  --set recyclarr.enabled=false \
  --wait \
  --timeout 120s

# Wait for Helm's delete requests to be fully processed by the GC
kubectl wait cronjob "${RELEASE}-recyclarr" \
  --kubeconfig "${KUBECONFIG}" -n "${NAMESPACE}" \
  --for=delete --timeout=180s 2>/dev/null || true
kubectl wait configmap "${RELEASE}-recyclarr-config" \
  --kubeconfig "${KUBECONFIG}" -n "${NAMESPACE}" \
  --for=delete --timeout=180s 2>/dev/null || true

check_not_exists "CronJob removed when Recyclarr disabled" \
  cronjob "${RELEASE}-recyclarr"
check_not_exists "ConfigMap removed when Recyclarr disabled" \
  configmap "${RELEASE}-recyclarr-config"

# ─── Summary ──────────────────────────────────────────────────────────────────

echo ""
if [[ "${FAIL}" -gt 0 ]]; then
  echo "RESULT: ${PASS} passed, ${FAIL} failed"
  exit 1
fi
echo "RESULT: ${PASS} passed — Recyclarr integration tests passed"
