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
Init config script for *arr services.
Writes config.xml to /config based on environment variables injected from the Secret.
Call with dict "root" . "port" 8989 "pgEnabled" true
*/}}
{{- define "arrmada.initConfigScript" -}}
{{- $port := .port -}}
{{- $pgEnabled := .pgEnabled -}}
#!/bin/sh
set -e
mkdir -p /config
cat > /config/config.xml << XMLEOF
<Config>
  <LogLevel>info</LogLevel>
  <UpdateMechanism>Docker</UpdateMechanism>
  <AnalyticsEnabled>False</AnalyticsEnabled>
  <ApiKey>${API_KEY}</ApiKey>
  <Port>{{ $port }}</Port>
  <UrlBase>${URL_BASE}</UrlBase>
{{- if $pgEnabled }}
  <PostgresHost>${PG_HOST}</PostgresHost>
  <PostgresPort>${PG_PORT}</PostgresPort>
  <PostgresUser>${PG_USER}</PostgresUser>
  <PostgresPassword>${PG_PASSWORD}</PostgresPassword>
  <PostgresMainDb>${PG_MAIN_DB}</PostgresMainDb>
  <PostgresLogDb>${PG_LOG_DB}</PostgresLogDb>
{{- end }}
</Config>
XMLEOF
echo "config.xml written successfully"
{{- end }}

{{/*
Auto-generate Prowlarr application entries for Sonarr and/or Radarr.
Combines autoSonarr/autoRadarr generated entries with extra entries from values.
Returns a JSON array suitable for use in the desired-state ConfigMap.
API keys use ${SONARR_API_KEY}/${RADARR_API_KEY} so they are resolved by envsubst
at runtime and never stored in plaintext in the ConfigMap.
*/}}
{{- define "arrmada.prowlarrAutoApplications" -}}
{{- $apps := list -}}
{{- if .Values.prowlarr.config.applications.autoSonarr }}
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
      (dict "name" "syncCategories" "value" (list 5000 5010 5020 5030 5040 5045 5050 5060 5070 5080))
    )
  -}}
  {{- $apps = append $apps $entry -}}
{{- end -}}
{{- if .Values.prowlarr.config.applications.autoRadarr }}
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
      (dict "name" "syncCategories" "value" (list 2000 2010 2020 2030 2040 2045 2050 2060 2070 2080))
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
to directly mirror the recyclarr.yml format (instance_name, quality_definition,
quality_profiles, custom_formats, delete_old_custom_formats).
*/}}
{{- define "arrmada.recyclarrConfig" -}}
{{- $root := . -}}
{{- if $root.Values.recyclarr.config.sonarr -}}
sonarr:
{{- range $root.Values.recyclarr.config.sonarr }}
  {{ .instance_name }}:
    base_url: {{ include "arrmada.sonarrUrl" $root }}
    api_key: !env_var SONARR_API_KEY
    {{- if .quality_definition }}
    quality_definition:
{{ .quality_definition | toYaml | indent 6 -}}
    {{- end }}
    {{- if .quality_profiles }}
    quality_profiles:
{{ .quality_profiles | toYaml | indent 4 -}}
    {{- end }}
    {{- if .custom_formats }}
    custom_formats:
{{ .custom_formats | toYaml | indent 4 -}}
    {{- end }}
    {{- if .delete_old_custom_formats }}
    delete_old_custom_formats: {{ .delete_old_custom_formats }}
    {{- end }}
{{- end }}
{{- end }}
{{- if $root.Values.recyclarr.config.radarr }}
radarr:
{{- range $root.Values.recyclarr.config.radarr }}
  {{ .instance_name }}:
    base_url: {{ include "arrmada.radarrUrl" $root }}
    api_key: !env_var RADARR_API_KEY
    {{- if .quality_definition }}
    quality_definition:
{{ .quality_definition | toYaml | indent 6 -}}
    {{- end }}
    {{- if .quality_profiles }}
    quality_profiles:
{{ .quality_profiles | toYaml | indent 4 -}}
    {{- end }}
    {{- if .custom_formats }}
    custom_formats:
{{ .custom_formats | toYaml | indent 4 -}}
    {{- end }}
    {{- if .delete_old_custom_formats }}
    delete_old_custom_formats: {{ .delete_old_custom_formats }}
    {{- end }}
{{- end }}
{{- end }}
{{- end }}
