#!/bin/sh
# helpers.sh — shared logging and API functions for config-sync

# ─── Logging ──────────────────────────────────────────────────────────────────

log()   { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] $*"; }
info()  { log "INFO  $*"; }
warn()  { log "WARN  $*" >&2; }
error() { log "ERROR $*" >&2; }
die()   { error "$*"; exit 1; }

# ─── API helpers ──────────────────────────────────────────────────────────────

# api_get <base_url> <api_version> <api_key> <resource>
api_get() {
  local base_url="$1" api_version="$2" api_key="$3" resource="$4"
  curl -sf \
    -H "X-Api-Key: ${api_key}" \
    "${base_url}/api/${api_version}/${resource}"
}

# api_post <base_url> <api_version> <api_key> <resource> <body>
api_post() {
  local base_url="$1" api_version="$2" api_key="$3" resource="$4" body="$5"
  curl -sf -X POST \
    -H "X-Api-Key: ${api_key}" \
    -H "Content-Type: application/json" \
    -d "${body}" \
    "${base_url}/api/${api_version}/${resource}"
}

# api_put <base_url> <api_version> <api_key> <resource> <id> <body>
api_put() {
  local base_url="$1" api_version="$2" api_key="$3" resource="$4" id="$5" body="$6"
  curl -sf -X PUT \
    -H "X-Api-Key: ${api_key}" \
    -H "Content-Type: application/json" \
    -d "${body}" \
    "${base_url}/api/${api_version}/${resource}/${id}"
}

# api_delete <base_url> <api_version> <api_key> <resource> <id>
api_delete() {
  local base_url="$1" api_version="$2" api_key="$3" resource="$4" id="$5"
  curl -sf -X DELETE \
    -H "X-Api-Key: ${api_key}" \
    "${base_url}/api/${api_version}/${resource}/${id}"
}

# ─── Utility ──────────────────────────────────────────────────────────────────

# wait_for_api <base_url> <api_version> <api_key> <timeout_seconds>
# Polls /api/<version>/system/status until it returns 200 or timeout expires.
wait_for_api() {
  local base_url="$1" api_version="$2" api_key="$3" timeout="${4:-300}"
  local deadline=$(($(date +%s) + timeout))
  local endpoint="${base_url}/api/${api_version}/system/status"

  info "Waiting for API at ${endpoint} (timeout: ${timeout}s)"
  while [ "$(date +%s)" -lt "${deadline}" ]; do
    if curl -sf -H "X-Api-Key: ${api_key}" "${endpoint}" > /dev/null 2>&1; then
      info "API is ready"
      return 0
    fi
    sleep 5
  done
  error "API did not become ready within ${timeout}s"
  return 1
}
