#!/bin/bash
# Verify Prowlarr→Sonarr and Prowlarr→Radarr application connections were created.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="${SCRIPT_DIR}/.."

export KUBECONFIG="${KUBECONFIG:-${TESTS_DIR}/.kubeconfig}"
NAMESPACE="arrmada-test"
RELEASE="arrmada-test"

PASS=0
FAIL=0

# Ensure background port-forward is killed on exit/error
PF_PID=""
cleanup() {
  if [[ -n "${PF_PID}" ]]; then
    kill "${PF_PID}" 2>/dev/null || true
    wait "${PF_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

check_contains() {
  local desc="$1"
  local haystack="$2"
  local needle="$3"
  if echo "${haystack}" | grep -qi "${needle}"; then
    echo "  PASS: ${desc}"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: ${desc} (needle '${needle}' not found)"
    echo "        Response: ${haystack}"
    FAIL=$((FAIL + 1))
  fi
}

# Get Prowlarr API key
PROWLARR_KEY=$(kubectl get secret "${RELEASE}-secrets" \
  --kubeconfig "${KUBECONFIG}" \
  -n "${NAMESPACE}" \
  -o "jsonpath={.data.prowlarr-api-key}" | base64 -d)

echo "Port-forwarding to Prowlarr..."
kubectl port-forward \
  --kubeconfig "${KUBECONFIG}" \
  -n "${NAMESPACE}" \
  "svc/${RELEASE}-prowlarr" "39696:9696" &
PF_PID=$!
sleep 3

echo "Querying Prowlarr /api/v1/applications..."
apps=$(curl -s -H "X-Api-Key: ${PROWLARR_KEY}" \
  "http://localhost:39696/api/v1/applications" || echo "[]")

check_contains "Prowlarr has Sonarr application connection" "${apps}" "sonarr"
check_contains "Prowlarr has Radarr application connection" "${apps}" "radarr"

kill "${PF_PID}" 2>/dev/null || true
wait "${PF_PID}" 2>/dev/null || true

echo ""
if [[ "${FAIL}" -gt 0 ]]; then
  echo "RESULT: ${PASS} passed, ${FAIL} failed"
  exit 1
fi
echo "RESULT: ${PASS} passed — Prowlarr application connections verified"
