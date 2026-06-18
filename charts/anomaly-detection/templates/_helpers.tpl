{{/*
Expand the name of the chart.
*/}}
{{- define "staffops-ad.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "staffops-ad.fullname" -}}
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
Per-component fullnames. Keeps controller/worker/ml/redis distinct.
*/}}
{{- define "staffops-ad.controller.fullname" -}}
{{- printf "%s-controller" (include "staffops-ad.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "staffops-ad.worker.fullname" -}}
{{- printf "%s-worker" (include "staffops-ad.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "staffops-ad.ml.fullname" -}}
{{- printf "%s-ml" (include "staffops-ad.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "staffops-ad.redis.fullname" -}}
{{- printf "%s-redis" (include "staffops-ad.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "staffops-ad.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels — applied to every resource managed by this chart.
*/}}
{{- define "staffops-ad.labels" -}}
helm.sh/chart: {{ include "staffops-ad.chart" . }}
{{ include "staffops-ad.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: staffops-anomaly-detection
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Selector labels — used in Deployment selectors. NEVER include version
(otherwise rolling updates fail because the selector becomes immutable).
*/}}
{{- define "staffops-ad.selectorLabels" -}}
app.kubernetes.io/name: {{ include "staffops-ad.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Per-component selector labels.
*/}}
{{- define "staffops-ad.controller.selectorLabels" -}}
{{ include "staffops-ad.selectorLabels" . }}
app.kubernetes.io/component: controller
{{- end }}

{{- define "staffops-ad.worker.selectorLabels" -}}
{{ include "staffops-ad.selectorLabels" . }}
app.kubernetes.io/component: worker
{{- end }}

{{- define "staffops-ad.ml.selectorLabels" -}}
{{ include "staffops-ad.selectorLabels" . }}
app.kubernetes.io/component: ml
{{- end }}

{{- define "staffops-ad.redis.selectorLabels" -}}
{{ include "staffops-ad.selectorLabels" . }}
app.kubernetes.io/component: redis
{{- end }}

{{/*
Per-component labels (selector + version + common).
*/}}
{{- define "staffops-ad.controller.labels" -}}
{{ include "staffops-ad.labels" . }}
app.kubernetes.io/component: controller
{{- end }}

{{- define "staffops-ad.worker.labels" -}}
{{ include "staffops-ad.labels" . }}
app.kubernetes.io/component: worker
{{- end }}

{{- define "staffops-ad.ml.labels" -}}
{{ include "staffops-ad.labels" . }}
app.kubernetes.io/component: ml
{{- end }}

{{- define "staffops-ad.redis.labels" -}}
{{ include "staffops-ad.labels" . }}
app.kubernetes.io/component: redis
{{- end }}

{{/*
ServiceAccount name to use.
*/}}
{{- define "staffops-ad.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "staffops-ad.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Image references (registry / repository : tag).
Each component (controller, worker, ml) has its own image with fallback to
the top-level .Values.image for registry/tag/pullPolicy when component-level
fields are empty. Tag also falls back to .Chart.AppVersion.
*/}}
{{- define "staffops-ad.controller.image" -}}
{{- $registry := default .Values.image.registry .Values.controller.image.registry -}}
{{- $repo := .Values.controller.image.repository -}}
{{- $tag := default (default .Chart.AppVersion .Values.image.tag) .Values.controller.image.tag -}}
{{- printf "%s/%s:%s" $registry $repo $tag -}}
{{- end }}

{{- define "staffops-ad.controller.imagePullPolicy" -}}
{{- default .Values.image.pullPolicy .Values.controller.image.pullPolicy -}}
{{- end }}

{{- define "staffops-ad.worker.image" -}}
{{- $registry := default .Values.image.registry .Values.worker.image.registry -}}
{{- $repo := .Values.worker.image.repository -}}
{{- $tag := default (default .Chart.AppVersion .Values.image.tag) .Values.worker.image.tag -}}
{{- printf "%s/%s:%s" $registry $repo $tag -}}
{{- end }}

{{- define "staffops-ad.worker.imagePullPolicy" -}}
{{- default .Values.image.pullPolicy .Values.worker.image.pullPolicy -}}
{{- end }}

{{- define "staffops-ad.ml.image" -}}
{{- $registry := default .Values.image.registry .Values.ml.image.registry -}}
{{- $repo := .Values.ml.image.repository -}}
{{- $tag := default (default .Chart.AppVersion .Values.image.tag) .Values.ml.image.tag -}}
{{- printf "%s/%s:%s" $registry $repo $tag -}}
{{- end }}

{{- define "staffops-ad.ml.imagePullPolicy" -}}
{{- default .Values.image.pullPolicy .Values.ml.image.pullPolicy -}}
{{- end }}

{{- define "staffops-ad.redis.image" -}}
{{- $registry := .Values.redis.image.registry -}}
{{- $repo := .Values.redis.image.repository -}}
{{- $tag := .Values.redis.image.tag -}}
{{- printf "%s/%s:%s" $registry $repo $tag -}}
{{- end }}

{{/*
Resolve the Redis address — either the in-cluster Redis service or external addr.
Used by controller and worker deployments to set REDIS_ADDR.
*/}}
{{- define "staffops-ad.redis.addr" -}}
{{- if .Values.redis.enabled -}}
{{ include "staffops-ad.redis.fullname" . }}:6379
{{- else -}}
{{ required "redis.external.addr is required when redis.enabled=false" .Values.redis.external.addr }}
{{- end -}}
{{- end }}

{{/*
Worker gRPC endpoint used by the controller.
Uses dns:/// scheme to enable gRPC client-side round-robin across worker pod IPs.
Pairs with a headless service (clusterIP: None) on the worker side.
*/}}
{{- define "staffops-ad.worker.endpoint" -}}
dns:///{{ include "staffops-ad.worker.fullname" . }}:{{ .Values.worker.grpcPort }}
{{- end }}

{{/*
ML gRPC endpoint used by the controller.
*/}}
{{- define "staffops-ad.ml.endpoint" -}}
{{ include "staffops-ad.ml.fullname" . }}:{{ .Values.ml.grpcPort }}
{{- end }}
