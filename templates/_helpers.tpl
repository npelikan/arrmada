{{/*
Expand the name of the chart.
*/}}
{{- define "arrmada.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "arrmada.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "arrmada.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "arrmada.labels" -}}
helm.sh/chart: {{ include "arrmada.chart" . }}
{{ include "arrmada.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "arrmada.selectorLabels" -}}
app.kubernetes.io/name: {{ include "arrmada.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Component-scoped full name. Call with dict "root" . "component" "sonarr"
*/}}
{{- define "arrmada.componentName" -}}
{{- $root := .root -}}
{{- $component := .component -}}
{{- printf "%s-%s" (include "arrmada.fullname" $root) $component | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Component labels. Call with dict "root" . "component" "sonarr"
*/}}
{{- define "arrmada.componentLabels" -}}
{{- $root := .root -}}
{{- $component := .component -}}
helm.sh/chart: {{ include "arrmada.chart" $root }}
{{ include "arrmada.componentSelectorLabels" (dict "root" $root "component" $component) }}
{{- if $root.Chart.AppVersion }}
app.kubernetes.io/version: {{ $root.Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ $root.Release.Service }}
{{- end }}

{{/*
Component selector labels. Call with dict "root" . "component" "sonarr"
*/}}
{{- define "arrmada.componentSelectorLabels" -}}
{{- $root := .root -}}
{{- $component := .component -}}
app.kubernetes.io/name: {{ include "arrmada.name" $root }}
app.kubernetes.io/instance: {{ $root.Release.Name }}
app.kubernetes.io/component: {{ $component }}
{{- end }}

{{/*
Service account name
*/}}
{{- define "arrmada.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "arrmada.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Name of the Secret containing API keys and credentials.
When global.existingSecret is set, returns that name; otherwise the chart-managed Secret.
*/}}
{{- define "arrmada.secretName" -}}
{{- if .Values.global.existingSecret }}
{{- .Values.global.existingSecret }}
{{- else }}
{{- include "arrmada.fullname" . }}-secrets
{{- end }}
{{- end }}

{{/*
Internal service URL for Sonarr (used by config sync and Prowlarr auto-app).
*/}}
{{- define "arrmada.sonarrUrl" -}}
{{- printf "http://%s-sonarr:%d" (include "arrmada.fullname" .) (.Values.sonarr.service.port | int) }}
{{- end }}

{{/*
Internal service URL for Radarr.
*/}}
{{- define "arrmada.radarrUrl" -}}
{{- printf "http://%s-radarr:%d" (include "arrmada.fullname" .) (.Values.radarr.service.port | int) }}
{{- end }}

{{/*
Internal service URL for Prowlarr.
*/}}
{{- define "arrmada.prowlarrUrl" -}}
{{- printf "http://%s-prowlarr:%d" (include "arrmada.fullname" .) (.Values.prowlarr.service.port | int) }}
{{- end }}

{{/*
Internal service URL for rtorrent RPC endpoint (used by Sonarr/Radarr download client).
*/}}
{{- define "arrmada.rtorrentUrl" -}}
{{- printf "http://%s-rtorrent:%d" (include "arrmada.fullname" .) (.Values.rtorrent.service.rpcPort | int) }}
{{- end }}

{{/*
Volume mount entries for all global.media volumes.
Outputs YAML list items without a leading newline; use with nindent.
*/}}
{{- define "arrmada.globalMediaVolumeMounts" -}}
{{- range $i, $v := .Values.global.media -}}
{{- if gt $i 0 }}
{{ end -}}
- name: media-{{ $v.name }}
  mountPath: {{ $v.mountPath }}
{{- end -}}
{{- end }}

{{/*
Volume definitions for all global.media volumes.
Outputs YAML list items without a leading newline; use with nindent.
*/}}
{{- define "arrmada.globalMediaVolumes" -}}
{{- $root := . -}}
{{- range $i, $v := .Values.global.media -}}
{{- if gt $i 0 }}
{{ end -}}
- name: media-{{ $v.name }}
  persistentVolumeClaim:
    claimName: {{ $v.existingClaim | default (printf "%s-media-%s" (include "arrmada.fullname" $root) $v.name) }}
{{- end -}}
{{- end }}

{{/*
Sonarr root folders: merges explicit sonarr.config.rootFolders with tvDir entries
from each global.media volume. Returns a JSON array.
*/}}
{{- define "arrmada.sonarrRootFolders" -}}
{{- $folders := .Values.sonarr.config.rootFolders | default list -}}
{{- range .Values.global.media -}}
  {{- if .tvDir -}}
    {{- $folders = append $folders (dict "path" .tvDir) -}}
  {{- end -}}
{{- end -}}
{{- $folders | toJson -}}
{{- end }}

{{/*
Radarr root folders: merges explicit radarr.config.rootFolders with moviesDir entries
from each global.media volume. Returns a JSON array.
*/}}
{{- define "arrmada.radarrRootFolders" -}}
{{- $folders := .Values.radarr.config.rootFolders | default list -}}
{{- range .Values.global.media -}}
  {{- if .moviesDir -}}
    {{- $folders = append $folders (dict "path" .moviesDir) -}}
  {{- end -}}
{{- end -}}
{{- $folders | toJson -}}
{{- end }}

{{/*
Returns a non-empty string if any global.media entry has a downloadDir set.
Use with `if include "arrmada.rtorrentHasDownloadDirs" .` to conditionally
render the rtorrent download-directory init container.
*/}}
{{- define "arrmada.rtorrentHasDownloadDirs" -}}
{{- range .Values.global.media -}}
  {{- if .downloadDir -}}true{{- end -}}
{{- end -}}
{{- end }}

{{/*
Auto-generate the rTorrent download client entry for Sonarr.
Returns a JSON object (not array) representing one download client.
*/}}
{{- define "arrmada.rtorrentDownloadClientSonarr" -}}
{{- dict
    "name" "rTorrent"
    "enable" true
    "implementation" "rTorrent"
    "configContract" "rTorrentSettings"
    "priority" 1
    "fields" (list
      (dict "name" "host" "value" (printf "%s-rtorrent" (include "arrmada.fullname" .)))
      (dict "name" "port" "value" (.Values.rtorrent.service.rpcPort | int))
      (dict "name" "urlBase" "value" "/RPC2")
      (dict "name" "username" "value" "")
      (dict "name" "password" "value" "")
      (dict "name" "tvCategory" "value" "tv-sonarr")
      (dict "name" "recentTvPriority" "value" 0)
      (dict "name" "olderTvPriority" "value" 0)
      (dict "name" "addStopped" "value" false)
    )
| toJson -}}
{{- end }}

{{/*
Auto-generate the rTorrent download client entry for Radarr.
Returns a JSON object (not array) representing one download client.
*/}}
{{- define "arrmada.rtorrentDownloadClientRadarr" -}}
{{- dict
    "name" "rTorrent"
    "enable" true
    "implementation" "rTorrent"
    "configContract" "rTorrentSettings"
    "priority" 1
    "fields" (list
      (dict "name" "host" "value" (printf "%s-rtorrent" (include "arrmada.fullname" .)))
      (dict "name" "port" "value" (.Values.rtorrent.service.rpcPort | int))
      (dict "name" "urlBase" "value" "/RPC2")
      (dict "name" "username" "value" "")
      (dict "name" "password" "value" "")
      (dict "name" "movieCategory" "value" "radarr")
      (dict "name" "recentMoviePriority" "value" 0)
      (dict "name" "olderMoviePriority" "value" 0)
      (dict "name" "addStopped" "value" false)
    )
| toJson -}}
{{- end }}

{{/*
Init config script for *arr services.
Writes config.xml to /config based on environment variables injected from the Secret.
Call with dict "root" . "port" 8989 "pgEnabled" true

NOTE: XML special characters (&, <, >, ", ') in secrets are escaped at write time
using a shell xml_escape helper to prevent malformed config.xml on startup.
*/}}
{{- define "arrmada.initConfigScript" -}}
{{- $port := .port -}}
{{- $pgEnabled := .pgEnabled -}}
#!/bin/sh
set -e

# Escape XML special characters in a value.
# Usage: xml_escape "$VALUE"
xml_escape() {
  printf '%s' "$1" \
    | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g; s/'"'"'/\&apos;/g'
}

mkdir -p /config
{
  printf '<Config>\n'
  printf '  <LogLevel>info</LogLevel>\n'
  printf '  <UpdateMechanism>Docker</UpdateMechanism>\n'
  printf '  <AnalyticsEnabled>False</AnalyticsEnabled>\n'
  printf '  <ApiKey>%s</ApiKey>\n'       "$(xml_escape "${API_KEY}")"
  printf '  <Port>{{ $port }}</Port>\n'
  printf '  <UrlBase>%s</UrlBase>\n'     "$(xml_escape "${URL_BASE}")"
{{- if $pgEnabled }}
  printf '  <PostgresHost>%s</PostgresHost>\n'     "$(xml_escape "${PG_HOST}")"
  printf '  <PostgresPort>%s</PostgresPort>\n'     "$(xml_escape "${PG_PORT}")"
  printf '  <PostgresUser>%s</PostgresUser>\n'     "$(xml_escape "${PG_USER}")"
  printf '  <PostgresPassword>%s</PostgresPassword>\n' "$(xml_escape "${PG_PASSWORD}")"
  printf '  <PostgresMainDb>%s</PostgresMainDb>\n' "$(xml_escape "${PG_MAIN_DB}")"
  printf '  <PostgresLogDb>%s</PostgresLogDb>\n'   "$(xml_escape "${PG_LOG_DB}")"
{{- end }}
  printf '</Config>\n'
} > /config/config.xml
# Allow the service user (PUID) to read and write the file.
# The init container runs as root; the main container runs as the hotio user.
chmod 666 /config/config.xml
echo "config.xml written successfully"
{{- end }}

{{/*
Auto-generate Prowlarr application entries for Sonarr and/or Radarr.
Combines autoSonarr/autoRadarr generated entries with extra entries from values.
Returns a JSON array suitable for use in the desired-state ConfigMap.
API keys use ${SONARR_API_KEY}/${RADARR_API_KEY} so they are resolved by jq's
env object (via resolve_env_vars in sync-resource.sh) at runtime and never
stored in plaintext in the ConfigMap.

BREAKING CHANGE (v0.2.0): prowlarr.config.applications must be a dict
(autoSonarr, autoRadarr, extra), not a list. Helm will fail with a type error
if the old list format is supplied.
*/}}
{{- define "arrmada.prowlarrAutoApplications" -}}
{{- if kindIs "slice" .Values.prowlarr.config.applications -}}
  {{- fail "prowlarr.config.applications must be a dict (autoSonarr/autoRadarr/extra), not a list. See values.yaml for the v0.2.0 migration guide." -}}
{{- end -}}
{{- $apps := list -}}
{{- if .Values.prowlarr.config.applications.autoSonarr }}
  {{- $sonarrCats := (list 5000 5010 5020 5030 5040 5045 5050 5060 5070 5080) -}}
  {{- if hasKey .Values.prowlarr.config.applications "sonarrSyncCategories" -}}
    {{- $sonarrCats = .Values.prowlarr.config.applications.sonarrSyncCategories -}}
  {{- end -}}
  {{- $entry := dict
    "name" "Sonarr"
    "syncLevel" "fullSync"
    "implementationName" "Sonarr"
    "implementation" "Sonarr"
    "configContract" "SonarrSettings"
    "fields" (list
      (dict "name" "prowlarrUrl" "value" (include "arrmada.prowlarrUrl" .))
      (dict "name" "baseUrl" "value" (include "arrmada.sonarrUrl" .))
      (dict "name" "apiKey" "value" "${SONARR_API_KEY}")
      (dict "name" "syncCategories" "value" $sonarrCats)
    )
  -}}
  {{- $apps = append $apps $entry -}}
{{- end -}}
{{- if .Values.prowlarr.config.applications.autoRadarr }}
  {{- $radarrCats := (list 2000 2010 2020 2030 2040 2045 2050 2060 2070 2080) -}}
  {{- if hasKey .Values.prowlarr.config.applications "radarrSyncCategories" -}}
    {{- $radarrCats = .Values.prowlarr.config.applications.radarrSyncCategories -}}
  {{- end -}}
  {{- $entry := dict
    "name" "Radarr"
    "syncLevel" "fullSync"
    "implementationName" "Radarr"
    "implementation" "Radarr"
    "configContract" "RadarrSettings"
    "fields" (list
      (dict "name" "prowlarrUrl" "value" (include "arrmada.prowlarrUrl" .))
      (dict "name" "baseUrl" "value" (include "arrmada.radarrUrl" .))
      (dict "name" "apiKey" "value" "${RADARR_API_KEY}")
      (dict "name" "syncCategories" "value" $radarrCats)
    )
  -}}
  {{- $apps = append $apps $entry -}}
{{- end -}}
{{- range .Values.prowlarr.config.applications.extra -}}
  {{- $apps = append $apps . -}}
{{- end -}}
{{- $apps | toJson -}}
{{- end }}

{{/*
Generate recyclarr.yml content from values.
Service URLs are auto-populated; API keys use !env_var so they are not stored
in the ConfigMap in plaintext.

Note: the recyclarr.config.sonarr/radarr values use snake_case field names
to directly mirror the recyclarr.yml format (quality_definition,
quality_profiles, custom_formats, delete_old_custom_formats).

Each of recyclarr.config.sonarr and recyclarr.config.radarr is a single
instance object (not a list). The instance key in the generated YAML is
always "main" since each service has exactly one internal endpoint.

Constraint: the hardcoded "main" instance key couples this template to
Recyclarr's single-instance-per-service model. Supporting multiple Sonarr
or Radarr instances would require a schema change (list of objects with
name keys) and a new template iteration approach. Do not extend this
template for multi-instance use without updating the schema and tests.
*/}}
{{- define "arrmada.recyclarrConfig" -}}
{{- $root := . -}}
{{- if $root.Values.recyclarr.config.sonarr -}}
{{- $sonarr := $root.Values.recyclarr.config.sonarr -}}
sonarr:
  main:
    base_url: {{ include "arrmada.sonarrUrl" $root }}
    api_key: !env_var SONARR_API_KEY
    {{- if $sonarr.quality_definition }}
    quality_definition:
{{ $sonarr.quality_definition | toYaml | indent 6 -}}
    {{- end }}
    {{- if $sonarr.quality_profiles }}
    quality_profiles:
{{ $sonarr.quality_profiles | toYaml | indent 6 -}}
    {{- end }}
    {{- if $sonarr.custom_formats }}
    custom_formats:
{{ $sonarr.custom_formats | toYaml | indent 6 -}}
    {{- end }}
    {{- if hasKey $sonarr "delete_old_custom_formats" }}
    delete_old_custom_formats: {{ $sonarr.delete_old_custom_formats }}
    {{- end }}
{{- end }}
{{- if $root.Values.recyclarr.config.radarr }}
{{- $radarr := $root.Values.recyclarr.config.radarr -}}
radarr:
  main:
    base_url: {{ include "arrmada.radarrUrl" $root }}
    api_key: !env_var RADARR_API_KEY
    {{- if $radarr.quality_definition }}
    quality_definition:
{{ $radarr.quality_definition | toYaml | indent 6 -}}
    {{- end }}
    {{- if $radarr.quality_profiles }}
    quality_profiles:
{{ $radarr.quality_profiles | toYaml | indent 6 -}}
    {{- end }}
    {{- if $radarr.custom_formats }}
    custom_formats:
{{ $radarr.custom_formats | toYaml | indent 6 -}}
    {{- end }}
    {{- if hasKey $radarr "delete_old_custom_formats" }}
    delete_old_custom_formats: {{ $radarr.delete_old_custom_formats }}
    {{- end }}
{{- end }}
{{- end }}
