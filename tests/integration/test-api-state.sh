#!/bin/bash
# Verify declarative config was applied by querying each service's API.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="${SCRIPT_DIR}/.."

export KUBECONFIG="${TESTS_DIR}/.kubeconfig.yml"
NAMESPACE="arrmada-test"
RELEASE="arrmada-test"

PASS=0
FAIL=0

# Track active port-forward PIDs for cleanup on exit
PF_PIDS=()

cleanup() {
  for pid in "${PF_PIDS[@]:-}"; do
    kill "${pid}" 2>/dev/null || true
    wait "${pid}" 2>/dev/null || true
  done
}
trap cleanup EXIT

check() {
  local desc="$1"
  local result="$2"
  if [[ -n "${result}" && "${result}" != "null" && "${result}" != "[]" ]]; then
    echo "  PASS: ${desc}"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: ${desc} (got: '${result}')"
    FAIL=$((FAIL + 1))
  fi
}

# Port-forward helper — starts a port-forward in background and registers it for cleanup
start_pf() {
  local svc="$1" port="$2" local_port="$3"
  kubectl port-forward \
    --kubeconfig "${KUBECONFIG}" \
    -n "${NAMESPACE}" \
    "svc/${RELEASE}-${svc}" "${local_port}:${port}" &
  local pid=$!
  PF_PIDS+=("${pid}")
  echo "${pid}"
}

# Fetch the API key from the chart Secret
get_api_key() {
  local key="$1"
  kubectl get secret "${RELEASE}-secrets" \
    --kubeconfig "${KUBECONFIG}" \
    -n "${NAMESPACE}" \
    -o "jsonpath={.data.${key}}" | base64 -d
}

echo "Fetching API keys from cluster Secret..."
SONARR_KEY="$(get_api_key "sonarr-api-key")"
RADARR_KEY="$(get_api_key "radarr-api-key")"
PROWLARR_KEY="$(get_api_key "prowlarr-api-key")"

echo ""
echo "=== Sonarr API state ==="
SONARR_PF_PID=$(start_pf sonarr 8989 28989)
sleep 3

# Root folders
root_folders=$(curl -s -H "X-Api-Key: ${SONARR_KEY}" \
  "http://localhost:28989/api/v3/rootfolder" || echo "[]")
check "Sonarr has root folders configured" "${root_folders}"

# Tags
tags=$(curl -s -H "X-Api-Key: ${SONARR_KEY}" \
  "http://localhost:28989/api/v3/tag" || echo "[]")
check "Sonarr has tags configured" "${tags}"

kill "${SONARR_PF_PID}" 2>/dev/null || true
wait "${SONARR_PF_PID}" 2>/dev/null || true

echo ""
echo "=== Radarr API state ==="
RADARR_PF_PID=$(start_pf radarr 7878 27878)
sleep 3

root_folders=$(curl -s -H "X-Api-Key: ${RADARR_KEY}" \
  "http://localhost:27878/api/v3/rootfolder" || echo "[]")
check "Radarr has root folders configured" "${root_folders}"

kill "${RADARR_PF_PID}" 2>/dev/null || true
wait "${RADARR_PF_PID}" 2>/dev/null || true

echo ""
echo "=== Prowlarr API state ==="
PROWLARR_PF_PID=$(start_pf prowlarr 9696 29696)
sleep 3

system_status=$(curl -s -H "X-Api-Key: ${PROWLARR_KEY}" \
  "http://localhost:29696/api/v1/system/status" || echo "")
check "Prowlarr API is reachable" "${system_status}"

kill "${PROWLARR_PF_PID}" 2>/dev/null || true
wait "${PROWLARR_PF_PID}" 2>/dev/null || true

echo ""
if [[ "${FAIL}" -gt 0 ]]; then
  echo "RESULT: ${PASS} passed, ${FAIL} failed"
  exit 1
fi
echo "RESULT: ${PASS} passed — declarative config verified via API"
