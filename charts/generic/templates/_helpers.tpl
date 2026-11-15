{{/*
Name of the app. Defaults to the release name (a generic chart has no
meaningful name of its own).
*/}}
{{- define "generic.name" -}}
{{- default .Release.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Fully qualified name used for every resource. Defaults to the release name.
*/}}
{{- define "generic.fullname" -}}
{{- default .Release.Name .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "generic.namespace" -}}
{{- default .Release.Namespace .Values.namespaceOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "generic.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Name for a child resource: <fullname>-<suffix>, truncated to 63 chars.
Usage: include "generic.childName" (list $ "suffix")
*/}}
{{- define "generic.childName" -}}
{{- $root := index . 0 -}}
{{- printf "%s-%s" (include "generic.fullname" $root) (index . 1) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "generic.selectorLabels" -}}
app.kubernetes.io/name: {{ include "generic.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "generic.labels" -}}
helm.sh/chart: {{ include "generic.chart" . }}
{{ include "generic.selectorLabels" . }}
{{- $version := include "generic.imageTag" . | trunc 63 | trimSuffix "-" | trimSuffix "_" | trimSuffix "." }}
{{- if $version }}
app.kubernetes.io/version: {{ $version | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.component }}
app.kubernetes.io/component: {{ . }}
{{- end }}
{{- with .Values.partOf }}
app.kubernetes.io/part-of: {{ . }}
{{- end }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
metadata.annotations block content (commonAnnotations merged with extra).
Usage: include "generic.annotations" (list $ .Values.x.annotations)
*/}}
{{- define "generic.annotations" -}}
{{- $root := index . 0 -}}
{{- $extra := index . 1 | default dict -}}
{{- $all := merge (deepCopy $extra) ($root.Values.commonAnnotations | default dict) -}}
{{- with $all }}
annotations:
  {{- tpl (toYaml .) $root | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Images
*/}}
{{- define "generic.imageTag" -}}
{{- .Values.image.tag | default .Chart.AppVersion | toString -}}
{{- end }}

{{- define "generic.image" -}}
{{- $registry := .Values.global.imageRegistry | default .Values.image.registry -}}
{{- $ref := .Values.image.repository -}}
{{- if $registry }}{{ $ref = printf "%s/%s" $registry $ref }}{{ end -}}
{{- if .Values.image.digest -}}
{{- printf "%s@%s" $ref .Values.image.digest -}}
{{- else -}}
{{- printf "%s:%s" $ref (include "generic.imageTag" .) -}}
{{- end -}}
{{- end }}

{{- define "generic.imagePullSecrets" -}}
{{- $secrets := list -}}
{{- range (concat (.Values.global.imagePullSecrets | default list) (.Values.imagePullSecrets | default list)) -}}
{{- if kindIs "map" . -}}
{{- $secrets = append $secrets .name -}}
{{- else -}}
{{- $secrets = append $secrets . -}}
{{- end -}}
{{- end -}}
{{- with ($secrets | uniq) }}
imagePullSecrets:
  {{- range . }}
  - name: {{ . }}
  {{- end }}
{{- end }}
{{- end }}

{{- define "generic.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "generic.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end }}

{{/*
Ports
*/}}
{{- define "generic.isExposed" -}}
{{- if or (not (hasKey . "expose")) .expose }}true{{ end -}}
{{- end }}

{{- define "generic.hasExposedPorts" -}}
{{- range .Values.ports }}{{ include "generic.isExposed" . }}{{ end -}}
{{- end }}

{{/* Service port number of the first exposed port. */}}
{{- define "generic.defaultServicePort" -}}
{{- $out := "" -}}
{{- range .Values.ports -}}
{{- if and (eq $out "") (include "generic.isExposed" .) -}}
{{- $out = toString (default .containerPort .servicePort) -}}
{{- end -}}
{{- end -}}
{{- $out -}}
{{- end }}

{{/* Name of the first exposed port. */}}
{{- define "generic.defaultPortName" -}}
{{- $out := "" -}}
{{- range .Values.ports -}}
{{- if and (eq $out "") (include "generic.isExposed" .) -}}
{{- $out = .name -}}
{{- end -}}
{{- end -}}
{{- $out -}}
{{- end }}

{{- define "generic.headlessServiceName" -}}
{{- default (include "generic.childName" (list . "headless")) .Values.workload.serviceName -}}
{{- end }}

{{- define "generic.serviceEnabled" -}}
{{- if and .Values.service.enabled (include "generic.hasExposedPorts" .) }}true{{ end -}}
{{- end }}

{{- define "generic.horizontalScaling" -}}
{{- if and (ne .Values.workload.kind "DaemonSet") (or .Values.autoscaling.enabled .Values.keda.enabled) }}true{{ end -}}
{{- end }}

{{/*
storageClassName: "" → omitted (cluster default), "-" → "" (no class / static PV).
Called with the persistence values.
*/}}
{{- define "generic.storageClass" -}}
{{- if eq (toString .storageClass) "-" }}
storageClassName: ""
{{- else if .storageClass }}
storageClassName: {{ .storageClass | quote }}
{{- end }}
{{- end }}
