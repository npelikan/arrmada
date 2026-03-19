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
