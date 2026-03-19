#!/bin/sh
# config-sync.sh — main entrypoint for declarative config sync
#
# Reads desired state from DESIRED_DIR (mounted ConfigMap), waits for each
# *arr service API to become ready, then converges configuration to match.
#
# Environment variables (set by Job template):
#   SONARR_ENABLED, SONARR_URL, SONARR_API_KEY, SONARR_API_VERSION
#   RADARR_ENABLED, RADARR_URL, RADARR_API_KEY, RADARR_API_VERSION
#   PROWLARR_ENABLED, PROWLARR_URL, PROWLARR_API_KEY, PROWLARR_API_VERSION
#   CONFIG_SYNC_TIMEOUT   — API readiness timeout in seconds (default: 300)
#   DELETE_UNMANAGED      — delete resources not in desired state (default: false)
#   DESIRED_DIR           — path to mounted desired-state ConfigMap (default: /desired-state)

set -e

# Install runtime dependencies (alpine base image)
apk add --no-cache curl jq > /dev/null 2>&1

# Source shared libraries (mounted flat from ConfigMap at /scripts/)
. /scripts/helpers.sh
. /scripts/sync-resource.sh

DESIRED_DIR="${DESIRED_DIR:-/desired-state}"
TIMEOUT="${CONFIG_SYNC_TIMEOUT:-300}"
export DELETE_UNMANAGED="${DELETE_UNMANAGED:-false}"

# ─── sync_service ─────────────────────────────────────────────────────────────
# Syncs all configured resources for a single service.
# Usage: sync_service <service_name>
sync_service() {
  local service="$1"
  local UPPER
  UPPER=$(echo "${service}" | tr '[:lower:]' '[:upper:]')

  # Resolve service-specific env vars
  local enabled url api_key api_version
  eval "enabled=\${${UPPER}_ENABLED:-false}"
  eval "url=\${${UPPER}_URL:-}"
  eval "api_key=\${${UPPER}_API_KEY:-}"
  eval "api_version=\${${UPPER}_API_VERSION:-v3}"

  if [ "${enabled}" != "true" ]; then
    info "Skipping ${service} (not enabled)"
    return 0
  fi

  if [ -z "${url}" ] || [ -z "${api_key}" ]; then
    warn "Skipping ${service}: missing URL or API key"
    return 0
  fi

  info "════════════════════════════════════"
  info "Syncing ${service}"
  info "════════════════════════════════════"

  # Wait for API readiness
  wait_for_api "${url}" "${api_version}" "${api_key}" "${TIMEOUT}" \
    || die "${service} API did not become ready within ${TIMEOUT}s"

  # ── Sync resources in dependency order ──────────────────────────────────────

  # 1. Tags
  local desired_file="${DESIRED_DIR}/${service}-tags.json"
  if [ -f "${desired_file}" ]; then
    local desired_tags
    desired_tags=$(cat "${desired_file}")
    if [ "${desired_tags}" != "[]" ] && [ -n "${desired_tags}" ]; then
      sync_resources "${url}" "${api_version}" "${api_key}" "tag" \
        "${desired_tags}" "label"
    else
      info "No tags configured for ${service}, skipping"
    fi
  fi

  # 2. Root Folders (Sonarr / Radarr only — Prowlarr has no rootfolder API)
  if [ "${service}" != "prowlarr" ]; then
    desired_file="${DESIRED_DIR}/${service}-rootfolders.json"
    if [ -f "${desired_file}" ]; then
      local desired_rf
      desired_rf=$(cat "${desired_file}")
      if [ "${desired_rf}" != "[]" ] && [ -n "${desired_rf}" ]; then
        sync_resources "${url}" "${api_version}" "${api_key}" "rootfolder" \
          "${desired_rf}" "path"
      else
        info "No root folders configured for ${service}, skipping"
      fi
    fi
  fi

  info "Done syncing ${service}"
}

# ─── Main ─────────────────────────────────────────────────────────────────────

info "Starting config sync"
info "DELETE_UNMANAGED=${DELETE_UNMANAGED}"
info "DESIRED_DIR=${DESIRED_DIR}"

sync_service sonarr
sync_service radarr
sync_service prowlarr

info "Config sync complete!"
