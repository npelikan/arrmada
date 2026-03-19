#!/bin/sh
# sync-resource.sh — generic desired-state sync functions
# Requires helpers.sh to be sourced first.

# sync_resources <base_url> <api_version> <api_key> <resource> <desired_json> [match_field]
#
# Converges <resource> list to match <desired_json>.
# - Creates items absent from current state (POST)
# - Updates items present in both (PUT, with id injected)
# - Optionally deletes items not in desired (DELETE) when DELETE_UNMANAGED=true
#
# <match_field> defaults to "name"; use "label" for tags, "path" for rootfolders.
sync_resources() {
  local base_url="$1" api_version="$2" api_key="$3" resource="$4" desired="$5"
  local match_field="${6:-name}"
  local delete_unmanaged="${DELETE_UNMANAGED:-false}"

  info "Syncing ${resource} (match by ${match_field})..."

  local current
  current=$(api_get "${base_url}" "${api_version}" "${api_key}" "${resource}") || {
    error "Failed to GET ${resource}"
    return 1
  }

  local desired_count
  desired_count=$(echo "${desired}" | jq 'length')

  local i=0
  while [ "${i}" -lt "${desired_count}" ]; do
    local item val existing_id merged

    item=$(echo "${desired}" | jq ".[${i}]")
    val=$(echo "${item}" | jq -r ".${match_field}")

    existing_id=$(echo "${current}" | jq -r \
      --arg v "${val}" --arg f "${match_field}" \
      '.[] | select(.[$f] == $v) | .id // empty')

    if [ -z "${existing_id}" ]; then
      info "  Creating ${resource}: ${val}"
      api_post "${base_url}" "${api_version}" "${api_key}" "${resource}" "${item}" \
        || warn "  Failed to create ${resource}: ${val}"
    else
      info "  Updating ${resource}: ${val} (id=${existing_id})"
      merged=$(echo "${item}" | jq --argjson id "${existing_id}" '. + {id: $id}')
      api_put "${base_url}" "${api_version}" "${api_key}" "${resource}" \
        "${existing_id}" "${merged}" \
        || warn "  Failed to update ${resource}: ${val}"
    fi

    i=$((i + 1))
  done

  # Optionally delete resources not in desired list
  if [ "${delete_unmanaged}" = "true" ]; then
    local current_count
    current_count=$(echo "${current}" | jq 'length')
    i=0
    while [ "${i}" -lt "${current_count}" ]; do
      local cur_val cur_id in_desired

      cur_val=$(echo "${current}" | jq -r ".[${i}].${match_field}")
      cur_id=$(echo "${current}" | jq -r ".[${i}].id")
      in_desired=$(echo "${desired}" | jq -r \
        --arg v "${cur_val}" --arg f "${match_field}" \
        'any(.[]; .[$f] == $v)')

      if [ "${in_desired}" = "false" ]; then
        info "  Deleting unmanaged ${resource}: ${cur_val} (id=${cur_id})"
        api_delete "${base_url}" "${api_version}" "${api_key}" "${resource}" "${cur_id}" \
          || warn "  Failed to delete ${resource}: ${cur_val}"
      fi

      i=$((i + 1))
    done
  fi

  info "Done syncing ${resource}"
}

# sync_singleton <base_url> <api_version> <api_key> <resource> <desired_json>
#
# GETs the current singleton resource to obtain its id, then PUTs the desired
# state with the id merged in.
sync_singleton() {
  local base_url="$1" api_version="$2" api_key="$3" resource="$4" desired="$5"

  info "Syncing singleton ${resource}..."

  local current
  current=$(api_get "${base_url}" "${api_version}" "${api_key}" "${resource}") || {
    error "Failed to GET ${resource}"
    return 1
  }

  local current_id body
  current_id=$(echo "${current}" | jq -r '.id // empty')

  if [ -n "${current_id}" ]; then
    body=$(echo "${desired}" | jq --argjson id "${current_id}" '. + {id: $id}')
    api_put "${base_url}" "${api_version}" "${api_key}" "${resource}" \
      "${current_id}" "${body}" \
      || { error "Failed to PUT ${resource}"; return 1; }
  else
    # No id in response (e.g. some config endpoints)
    api_put "${base_url}" "${api_version}" "${api_key}" "${resource}/0" \
      "0" "${desired}" \
      || { error "Failed to PUT ${resource}"; return 1; }
  fi

  info "Done syncing singleton ${resource}"
}

# sync_quality_definitions <base_url> <api_version> <api_key> <desired_json>
#
# Quality definitions always exist (they cannot be created or deleted).
# Matches by title and PUTs updates for any desired items found in the current list.
sync_quality_definitions() {
  local base_url="$1" api_version="$2" api_key="$3" desired="$4"

  info "Syncing qualitydefinition..."

  local current
  current=$(api_get "${base_url}" "${api_version}" "${api_key}" "qualitydefinition") || {
    error "Failed to GET qualitydefinition"
    return 1
  }

  local desired_count
  desired_count=$(echo "${desired}" | jq 'length')

  local i=0
  while [ "${i}" -lt "${desired_count}" ]; do
    local item title existing_id merged

    item=$(echo "${desired}" | jq ".[${i}]")
    title=$(echo "${item}" | jq -r '.title // empty')

    if [ -z "${title}" ]; then
      warn "  Quality definition at index ${i} has no title, skipping"
      i=$((i + 1))
      continue
    fi

    existing_id=$(echo "${current}" | jq -r \
      --arg t "${title}" '.[] | select(.title == $t) | .id // empty')

    if [ -z "${existing_id}" ]; then
      warn "  Quality definition '${title}' not found in current list, skipping"
    else
      info "  Updating qualitydefinition: ${title} (id=${existing_id})"
      # Merge desired fields INTO the full existing object so unspecified fields
      # (e.g. preferredSize, quality sub-object) are preserved rather than dropped.
      merged=$(echo "${current}" | jq \
        --argjson id "${existing_id}" --argjson item "${item}" \
        'map(select(.id == $id) | . + $item) | .[0]')
      api_put "${base_url}" "${api_version}" "${api_key}" "qualitydefinition" \
        "${existing_id}" "${merged}" \
        || warn "  Failed to update qualitydefinition: ${title}"
    fi

    i=$((i + 1))
  done

  info "Done syncing qualitydefinition"
}

# resolve_env_vars <json_string>
#
# Substitutes ${VAR} patterns found in JSON string values using jq's built-in
# env object. This is JSON-aware: values are injected as proper JSON strings so
# special characters (quotes, backslashes, newlines) cannot break the document.
#
# BREAKING CHANGE vs envsubst:
#   This function only replaces a JSON string value when it consists *entirely*
#   of a single "${VAR_NAME}" placeholder. Partial string interpolation such as
#   "http://${HOST}/path" is NOT supported. Move the full composed value into a
#   dedicated environment variable instead, e.g.:
#     export FULL_URL="http://myhost/path"   # then use "${FULL_URL}" in JSON
#
# Undefined variables: if VAR_NAME is not set in the environment the original
#   literal placeholder (e.g. "${MISSING}") is kept in the output. This differs
#   from envsubst, which would substitute an empty string. Inspect output values
#   that still look like "${...}" to catch unintentionally unset variables.
#
# Export requirement: jq reads variables from the process environment via
#   env[$var]. Variables must be exported (export VAR=val) before calling this
#   function; unexported shell variables are invisible to jq and will not be
#   substituted.
resolve_env_vars() {
  local input="$1"
  printf '%s' "${input}" | jq 'walk(
    if type == "string" and test("^\\$\\{[A-Za-z_][A-Za-z0-9_]*\\}$") then
      ltrimstr("${") | rtrimstr("}") | . as $var | env[$var] // .
    else
      .
    end
  )'
}
