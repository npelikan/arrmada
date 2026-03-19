#!/bin/bash
# Verify the rTorrent download client was synced to Sonarr and Radarr.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="${SCRIPT_DIR}/.."

export KUBECONFIG="${KUBECONFIG:-${TESTS_DIR}/.kubeconfig}"
NAMESPACE="arrmada-test"
RELEASE="arrmada-test"

PASS=0
FAIL=0

PF_PIDS=()
cleanup() {
  for pid in "${PF_PIDS[@]:-}"; do
    kill "${pid}" 2>/dev/null || true
    wait "${pid}" 2>/dev/null || true
  done
}
trap cleanup EXIT

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

check_contains() {
  local desc="$1" haystack="$2" needle="$3"
  if echo "${haystack}" | grep -qi "${needle}"; then
    echo "  PASS: ${desc}"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: ${desc} (expected '${needle}' in response)"
    echo "        Response: ${haystack}"
    FAIL=$((FAIL + 1))
  fi
}

SONARR_KEY="$(get_api_key "sonarr-api-key")"
RADARR_KEY="$(get_api_key "radarr-api-key")"

echo "=== Sonarr download clients ==="
start_pf sonarr 8989 48989
sleep 3

sonarr_clients=$(curl -s -H "X-Api-Key: ${SONARR_KEY}" \
  "http://localhost:48989/api/v3/downloadclient" || echo "[]")
check_contains "Sonarr has rTorrent download client" "${sonarr_clients}" "rtorrent"

echo ""
echo "=== Radarr download clients ==="
start_pf radarr 7878 47878
sleep 3

radarr_clients=$(curl -s -H "X-Api-Key: ${RADARR_KEY}" \
  "http://localhost:47878/api/v3/downloadclient" || echo "[]")
check_contains "Radarr has rTorrent download client" "${radarr_clients}" "rtorrent"

echo ""
if [[ "${FAIL}" -gt 0 ]]; then
  echo "RESULT: ${PASS} passed, ${FAIL} failed"
  exit 1
fi
echo "RESULT: ${PASS} passed — rTorrent download client verified in Sonarr and Radarr"
