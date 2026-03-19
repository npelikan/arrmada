#!/bin/bash
# Verify each service responds to /ping with HTTP 200.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="${SCRIPT_DIR}/.."

export KUBECONFIG="${TESTS_DIR}/.kubeconfig.yml"
NAMESPACE="arrmada-test"
RELEASE="arrmada-test"

PASS=0
FAIL=0

check_ping() {
  local svc="$1"
  local port="$2"
  local local_port="$3"

  echo "  Checking ${svc} /ping..."
  kubectl port-forward \
    --kubeconfig "${KUBECONFIG}" \
    -n "${NAMESPACE}" \
    "svc/${RELEASE}-${svc}" "${local_port}:${port}" &
  local pf_pid=$!
  sleep 3

  local status
  status=$(curl -s -o /dev/null -w "%{http_code}" \
    "http://localhost:${local_port}/ping" || echo "000")
  kill "${pf_pid}" 2>/dev/null || true
  wait "${pf_pid}" 2>/dev/null || true

  if [[ "${status}" == "200" ]]; then
    echo "  PASS: ${svc} /ping returned 200"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: ${svc} /ping returned ${status} (expected 200)"
    FAIL=$((FAIL + 1))
  fi
}

echo "Testing service /ping endpoints..."
check_ping "sonarr"   8989 18989
check_ping "radarr"   7878 17878
check_ping "prowlarr" 9696 19696

echo ""
if [[ "${FAIL}" -gt 0 ]]; then
  echo "RESULT: ${PASS} passed, ${FAIL} failed"
  exit 1
fi
echo "RESULT: ${PASS} passed — all services healthy"
