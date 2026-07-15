{{/*
Expand the name of the chart.
*/}}
{{- define "aigent-squad.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "aigent-squad.fullname" -}}
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
Per-service fully qualified name: <release-fullname>-<service>
*/}}
{{- define "aigent-squad.serviceFullname" -}}
{{- printf "%s-%s" (include "aigent-squad.fullname" .root) .name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Chart name + version for the chart label.
*/}}
{{- define "aigent-squad.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels (chart-wide). Pass the root context.
*/}}
{{- define "aigent-squad.labels" -}}
helm.sh/chart: {{ include "aigent-squad.chart" . }}
app.kubernetes.io/part-of: {{ include "aigent-squad.name" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- with .Values.global.labels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Per-service selector labels. Call with dict "root" $ "name" <service>.
*/}}
{{- define "aigent-squad.selectorLabels" -}}
app.kubernetes.io/name: {{ include "aigent-squad.serviceFullname" . }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/component: {{ .name }}
{{- end }}

{{/*
Per-service full label set. Call with dict "root" $ "name" <service>.
*/}}
{{- define "aigent-squad.serviceLabels" -}}
{{ include "aigent-squad.labels" .root }}
{{ include "aigent-squad.selectorLabels" . }}
{{- end }}

{{/*
Resolve a container image. Call with dict "root" $ "svc" <serviceValues>.
If the per-service repository contains "/" and a registry prefix is not already
present, the global registry is prepended. Kyverno may still rewrite it.
*/}}
{{- define "aigent-squad.image" -}}
{{- $reg := .root.Values.global.image.registry -}}
{{- $repo := dig "image" "repository" "aigent-squad/supervisor" .svc -}}
{{- $tag := dig "image" "tag" .root.Chart.AppVersion .svc -}}
{{- if $reg -}}
{{- printf "%s/%s:%s" $reg $repo $tag -}}
{{- else -}}
{{- printf "%s:%s" $repo $tag -}}
{{- end -}}
{{- end }}

{{/*
Per-service ServiceAccount name. Call with dict "root" $ "name" <service> "svc" <serviceValues>.
*/}}
{{- define "aigent-squad.serviceAccountName" -}}
{{- $create := dig "serviceAccount" "create" true .svc -}}
{{- $name := dig "serviceAccount" "name" "" .svc -}}
{{- if $create -}}
{{- default (include "aigent-squad.serviceFullname" (dict "root" .root "name" .name)) $name -}}
{{- else -}}
{{- default "default" $name -}}
{{- end -}}
{{- end }}

{{/*
Shared, non-sensitive env block as a list of name/value pairs.
Call with the root context ($). Includes global.env + OTel + backing services.
*/}}
{{- define "aigent-squad.commonEnv" -}}
{{- range $k, $v := .Values.global.env }}
- name: {{ $k }}
  value: {{ $v | quote }}
{{- end }}
- name: DYNAMODB_SESSIONS_TABLE
  value: {{ .Values.dynamodb.sessionsTable | quote }}
{{- if .Values.dynamodb.endpoint }}
- name: DYNAMODB_ENDPOINT
  value: {{ .Values.dynamodb.endpoint | quote }}
{{- end }}
{{- if .Values.redis.inCluster.enabled }}
- name: REDIS_HOST
  value: {{ printf "%s-redis" (include "aigent-squad.fullname" .) | quote }}
- name: REDIS_PORT
  value: {{ .Values.redis.port | quote }}
- name: REDIS_SSL
  value: "false"
{{- else if .Values.redis.host }}
- name: REDIS_HOST
  value: {{ .Values.redis.host | quote }}
- name: REDIS_PORT
  value: {{ .Values.redis.port | quote }}
- name: REDIS_SSL
  value: {{ .Values.redis.ssl | quote }}
{{- end }}
{{- if .Values.global.otel.enabled }}
- name: OTEL_EXPORTER_OTLP_ENDPOINT
  value: {{ .Values.global.otel.endpoint | quote }}
{{- if .Values.global.otel.metricsPrometheusScrape }}
- name: OTEL_METRICS_EXPORTER
  value: "otlp,prometheus"
- name: OTEL_HELPER_METRICS_PORT
  value: "0"
{{- end }}
{{- end }}
{{- end }}

{{/*
List of enabled services as a list of dicts {name, svc}.
Helper to iterate consistently across templates. Call with root ($).
*/}}
{{- define "aigent-squad.enabledServices" -}}
{{- $out := list -}}
{{- range $name, $svc := .Values.services -}}
{{- if $svc.enabled -}}
{{- $out = append $out $name -}}
{{- end -}}
{{- end -}}
{{- $out | toJson -}}
{{- end }}
