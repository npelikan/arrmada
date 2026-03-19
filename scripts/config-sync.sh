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
# gettext provides envsubst for ${ENV_VAR} substitution in sensitive fields
apk add --no-cache curl jq gettext > /dev/null 2>&1

# Source shared libraries (mounted flat from ConfigMap at /scripts/)
. /scripts/helpers.sh
. /scripts/sync-resource.sh

DESIRED_DIR="${DESIRED_DIR:-/desired-state}"
TIMEOUT="${CONFIG_SYNC_TIMEOUT:-300}"
export DELETE_UNMANAGED="${DELETE_UNMANAGED:-false}"

# ─── read_desired ──────────────────────────────────────────────────────────────
# Read a desired-state file, resolve ${ENV_VAR} patterns, and return the JSON.
# If the file doesn't exist or is empty/null/[], echoes "[]".
read_desired() {
  local path="$1"
  if [ ! -f "${path}" ]; then
    echo "[]"
    return 0
  fi
  local content
  content=$(cat "${path}")
  if [ -z "${content}" ] || [ "${content}" = "null" ]; then
    echo "[]"
    return 0
  fi
  resolve_env_vars "${content}"
}

# ─── read_desired_obj ──────────────────────────────────────────────────────────
# Like read_desired but for singleton objects; returns "{}" if not found.
read_desired_obj() {
  local path="$1"
  if [ ! -f "${path}" ]; then
    echo "{}"
    return 0
  fi
  local content
  content=$(cat "${path}")
  if [ -z "${content}" ] || [ "${content}" = "null" ] || [ "${content}" = "{}" ]; then
    echo "{}"
    return 0
  fi
  resolve_env_vars "${content}"
}

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
  local desired d="${DESIRED_DIR}/${service}"

  # 1. Tags (others may reference tag IDs)
  desired=$(read_desired "${d}-tags.json")
  if [ "${desired}" != "[]" ]; then
    sync_resources "${url}" "${api_version}" "${api_key}" "tag" \
      "${desired}" "label"
  fi

  # 2. Root folders (Sonarr / Radarr only — Prowlarr has no rootfolder API)
  if [ "${service}" != "prowlarr" ]; then
    desired=$(read_desired "${d}-rootfolders.json")
    if [ "${desired}" != "[]" ]; then
      sync_resources "${url}" "${api_version}" "${api_key}" "rootfolder" \
        "${desired}" "path"
    fi
  fi

  # ── Sonarr / Radarr-specific resources ──────────────────────────────────────
  if [ "${service}" != "prowlarr" ]; then

    # 3. Quality definitions (update-only, matched by title)
    desired=$(read_desired "${d}-qualitydefinitions.json")
    if [ "${desired}" != "[]" ]; then
      sync_quality_definitions "${url}" "${api_version}" "${api_key}" "${desired}"
    fi

    # 4. Custom formats (must exist before quality profiles reference them)
    desired=$(read_desired "${d}-customformats.json")
    if [ "${desired}" != "[]" ]; then
      sync_resources "${url}" "${api_version}" "${api_key}" "customformat" \
        "${desired}" "name"
    fi

    # 5. Quality profiles (reference custom formats by name)
    desired=$(read_desired "${d}-qualityprofiles.json")
    if [ "${desired}" != "[]" ]; then
      sync_resources "${url}" "${api_version}" "${api_key}" "qualityprofile" \
        "${desired}" "name"
    fi

    # 6. Delay profiles (matched by id; default profile is id=1)
    desired=$(read_desired "${d}-delayprofiles.json")
    if [ "${desired}" != "[]" ]; then
      sync_resources "${url}" "${api_version}" "${api_key}" "delayprofile" \
        "${desired}" "id"
    fi

    # 7. Download clients (may contain ${ENV_VAR} for passwords/API keys)
    desired=$(read_desired "${d}-downloadclients.json")
    if [ "${desired}" != "[]" ]; then
      sync_resources "${url}" "${api_version}" "${api_key}" "downloadclient" \
        "${desired}" "name"
    fi

    # 8. Notifications
    desired=$(read_desired "${d}-notifications.json")
    if [ "${desired}" != "[]" ]; then
      sync_resources "${url}" "${api_version}" "${api_key}" "notification" \
        "${desired}" "name"
    fi

    # 9. Import lists
    desired=$(read_desired "${d}-importlists.json")
    if [ "${desired}" != "[]" ]; then
      sync_resources "${url}" "${api_version}" "${api_key}" "importlist" \
        "${desired}" "name"
    fi

    # 10. Naming (singleton)
    desired=$(read_desired_obj "${d}-naming.json")
    if [ "${desired}" != "{}" ]; then
      sync_singleton "${url}" "${api_version}" "${api_key}" "config/naming" \
        "${desired}"
    fi

    # 11. Media management (singleton)
    desired=$(read_desired_obj "${d}-mediamanagement.json")
    if [ "${desired}" != "{}" ]; then
      sync_singleton "${url}" "${api_version}" "${api_key}" "config/mediamanagement" \
        "${desired}"
    fi

    # 12. Host settings (singleton)
    desired=$(read_desired_obj "${d}-host.json")
    if [ "${desired}" != "{}" ]; then
      sync_singleton "${url}" "${api_version}" "${api_key}" "config/host" \
        "${desired}"
    fi

    # 13. UI settings (singleton)
    desired=$(read_desired_obj "${d}-ui.json")
    if [ "${desired}" != "{}" ]; then
      sync_singleton "${url}" "${api_version}" "${api_key}" "config/ui" \
        "${desired}"
    fi

  fi # end Sonarr/Radarr-specific

  # ── Prowlarr-specific resources ─────────────────────────────────────────────
  if [ "${service}" = "prowlarr" ]; then

    # Download clients
    desired=$(read_desired "${d}-downloadclients.json")
    if [ "${desired}" != "[]" ]; then
      sync_resources "${url}" "${api_version}" "${api_key}" "downloadclient" \
        "${desired}" "name"
    fi

    # Notifications
    desired=$(read_desired "${d}-notifications.json")
    if [ "${desired}" != "[]" ]; then
      sync_resources "${url}" "${api_version}" "${api_key}" "notification" \
        "${desired}" "name"
    fi

    # Applications (Prowlarr→Sonarr/Radarr connections)
    desired=$(read_desired "${d}-applications.json")
    if [ "${desired}" != "[]" ]; then
      sync_resources "${url}" "${api_version}" "${api_key}" "applications" \
        "${desired}" "name"
    fi

    # General settings (singleton)
    desired=$(read_desired_obj "${d}-host.json")
    if [ "${desired}" != "{}" ]; then
      sync_singleton "${url}" "${api_version}" "${api_key}" "config/host" \
        "${desired}"
    fi

    # UI settings (singleton)
    desired=$(read_desired_obj "${d}-ui.json")
    if [ "${desired}" != "{}" ]; then
      sync_singleton "${url}" "${api_version}" "${api_key}" "config/ui" \
        "${desired}"
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
