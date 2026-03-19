#!/bin/sh
# wait-for-api.sh — standalone API readiness check
# Usage: wait-for-api.sh <base_url> <api_version> <api_key> [timeout_seconds]
#
# Exits 0 when the API is ready, 1 on timeout.

set -e

BASE_URL="${1}"
API_VERSION="${2}"
API_KEY="${3}"
TIMEOUT="${4:-300}"

if [ -z "${BASE_URL}" ] || [ -z "${API_VERSION}" ] || [ -z "${API_KEY}" ]; then
  echo "Usage: $0 <base_url> <api_version> <api_key> [timeout_seconds]" >&2
  exit 1
fi

DEADLINE=$(($(date +%s) + TIMEOUT))
ENDPOINT="${BASE_URL}/api/${API_VERSION}/system/status"

echo "Waiting for API at ${ENDPOINT} (timeout: ${TIMEOUT}s)"
while [ "$(date +%s)" -lt "${DEADLINE}" ]; do
  if curl -sf -H "X-Api-Key: ${API_KEY}" "${ENDPOINT}" > /dev/null 2>&1; then
    echo "API is ready"
    exit 0
  fi
  sleep 5
done

echo "ERROR: API did not become ready within ${TIMEOUT}s" >&2
exit 1
