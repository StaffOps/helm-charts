{{/*
Environment variables: `env` map (scalar → value through tpl, map → raw)
followed by the raw `extraEnv` list.
*/}}
{{- define "generic.env" -}}
{{- $root := . -}}
{{- range $k, $v := .Values.env }}
- name: {{ $k }}
  {{- if kindIs "map" $v }}
  {{- toYaml $v | nindent 2 }}
  {{- else }}
  value: {{ tpl (toString $v) $root | quote }}
  {{- end }}
{{- end }}
{{- with .Values.extraEnv }}
{{ tpl (toYaml .) $root }}
{{- end }}
{{- end }}

{{- define "generic.envFrom" -}}
{{- $root := . -}}
{{- range $k, $v := .Values.configMaps }}
{{- if $v.envFrom }}
- configMapRef:
    name: {{ include "generic.childName" (list $root $k) }}
{{- end }}
{{- end }}
{{- range $k, $v := .Values.secrets }}
{{- if $v.envFrom }}
- secretRef:
    name: {{ include "generic.childName" (list $root $k) }}
{{- end }}
{{- end }}
{{- range $k, $v := .Values.externalSecrets }}
{{- if $v.envFrom }}
- secretRef:
    name: {{ include "generic.childName" (list $root $k) }}
{{- end }}
{{- end }}
{{- with .Values.envFrom }}
{{ tpl (toYaml .) $root }}
{{- end }}
{{- end }}

{{- define "generic.volumeMounts" -}}
{{- $root := . -}}
{{- if .Values.tmpVolume.enabled }}
- name: tmp
  mountPath: {{ .Values.tmpVolume.mountPath }}
{{- end }}
{{- if .Values.persistence.enabled }}
- name: data
  mountPath: {{ .Values.persistence.mountPath }}
  {{- with .Values.persistence.subPath }}
  subPath: {{ . }}
  {{- end }}
{{- end }}
{{- range $prefix, $items := dict "cm" .Values.configMaps "secret" .Values.secrets "es" .Values.externalSecrets }}
{{- range $k, $v := $items }}
{{- if $v.mountPath }}
- name: {{ printf "%s-%s" $prefix $k | trunc 63 | trimSuffix "-" }}
  mountPath: {{ $v.mountPath }}
  readOnly: true
  {{- with $v.subPath }}
  subPath: {{ . }}
  {{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- with .Values.extraVolumeMounts }}
{{ tpl (toYaml .) $root }}
{{- end }}
{{- end }}

{{- define "generic.volumes" -}}
{{- $root := . -}}
{{- if .Values.tmpVolume.enabled }}
- name: tmp
  emptyDir:
    {{- with .Values.tmpVolume.medium }}
    medium: {{ . }}
    {{- end }}
    {{- with .Values.tmpVolume.sizeLimit }}
    sizeLimit: {{ . }}
    {{- end }}
{{- end }}
{{- if and .Values.persistence.enabled (or .Values.persistence.existingClaim (ne .Values.workload.kind "StatefulSet")) }}
- name: data
  persistentVolumeClaim:
    claimName: {{ .Values.persistence.existingClaim | default (include "generic.fullname" .) }}
{{- end }}
{{- range $k, $v := .Values.configMaps }}
{{- if $v.mountPath }}
- name: {{ printf "cm-%s" $k | trunc 63 | trimSuffix "-" }}
  configMap:
    name: {{ include "generic.childName" (list $root $k) }}
    {{- with $v.defaultMode }}
    defaultMode: {{ . }}
    {{- end }}
    {{- with $v.items }}
    items:
      {{- toYaml . | nindent 6 }}
    {{- end }}
{{- end }}
{{- end }}
{{- range $k, $v := (merge (deepCopy (.Values.secrets | default dict)) (.Values.externalSecrets | default dict)) }}
{{- if $v.mountPath }}
- name: {{ printf "%s-%s" (ternary "secret" "es" (hasKey $root.Values.secrets $k)) $k | trunc 63 | trimSuffix "-" }}
  secret:
    secretName: {{ include "generic.childName" (list $root $k) }}
    {{- with $v.defaultMode }}
    defaultMode: {{ . }}
    {{- end }}
    {{- with $v.items }}
    items:
      {{- toYaml . | nindent 6 }}
    {{- end }}
{{- end }}
{{- end }}
{{- with .Values.extraVolumes }}
{{ tpl (toYaml .) $root }}
{{- end }}
{{- end }}

{{- define "generic.affinity" -}}
{{- if .Values.affinity }}
affinity:
  {{- tpl (toYaml .Values.affinity) . | nindent 2 }}
{{- else if and .Values.podAntiAffinityPreset (ne .Values.workload.kind "DaemonSet") }}
affinity:
  podAntiAffinity:
    {{- if eq .Values.podAntiAffinityPreset "hard" }}
    requiredDuringSchedulingIgnoredDuringExecution:
      - topologyKey: kubernetes.io/hostname
        labelSelector:
          matchLabels:
            {{- include "generic.selectorLabels" . | nindent 12 }}
    {{- else }}
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          topologyKey: kubernetes.io/hostname
          labelSelector:
            matchLabels:
              {{- include "generic.selectorLabels" . | nindent 14 }}
    {{- end }}
{{- end }}
{{- end }}

{{- define "generic.topologySpreadConstraints" -}}
{{- $root := . -}}
{{- with .Values.topologySpreadConstraints }}
topologySpreadConstraints:
  {{- range . }}
  {{- $c := deepCopy . }}
  {{- if not $c.labelSelector }}
  {{- $_ := set $c "labelSelector" (dict "matchLabels" (include "generic.selectorLabels" $root | fromYaml)) }}
  {{- end }}
  - {{- toYaml $c | nindent 4 }}
  {{- end }}
{{- end }}
{{- end }}

{{/*
Pod template (metadata + spec) shared by Deployment/StatefulSet/DaemonSet.
*/}}
{{- define "generic.podTemplate" -}}
{{- $root := . -}}
metadata:
  labels:
    {{- include "generic.labels" . | nindent 4 }}
    {{- with .Values.podLabels }}
    {{- tpl (toYaml .) $root | nindent 4 }}
    {{- end }}
  {{- $ann := deepCopy (.Values.podAnnotations | default dict) }}
  {{- if .Values.rollOnConfigChange }}
  {{- if .Values.configMaps }}
  {{- $_ := set $ann "checksum/config" (include (print $.Template.BasePath "/configmap.yaml") . | sha256sum) }}
  {{- end }}
  {{- if or .Values.secrets .Values.externalSecrets }}
  {{- $_ := set $ann "checksum/secret" (print (include (print $.Template.BasePath "/secret.yaml") .) (toYaml .Values.externalSecrets) | sha256sum) }}
  {{- end }}
  {{- end }}
  {{- with $ann }}
  annotations:
    {{- tpl (toYaml .) $root | nindent 4 }}
  {{- end }}
spec:
  serviceAccountName: {{ include "generic.serviceAccountName" . }}
  automountServiceAccountToken: {{ or .Values.serviceAccount.automount .Values.rbac.create }}
  enableServiceLinks: {{ .Values.enableServiceLinks }}
  {{- with (include "generic.imagePullSecrets" . | trim) }}{{ . | nindent 2 }}{{ end }}
  {{- with .Values.priorityClassName }}
  priorityClassName: {{ . }}
  {{- end }}
  {{- with .Values.runtimeClassName }}
  runtimeClassName: {{ . }}
  {{- end }}
  {{- with .Values.schedulerName }}
  schedulerName: {{ . }}
  {{- end }}
  {{- if .Values.hostNetwork }}
  hostNetwork: true
  {{- end }}
  {{- if .Values.hostPID }}
  hostPID: true
  {{- end }}
  {{- if .Values.hostIPC }}
  hostIPC: true
  {{- end }}
  {{- if .Values.shareProcessNamespace }}
  shareProcessNamespace: true
  {{- end }}
  {{- if .Values.dnsPolicy }}
  dnsPolicy: {{ .Values.dnsPolicy }}
  {{- else if .Values.hostNetwork }}
  dnsPolicy: ClusterFirstWithHostNet
  {{- end }}
  {{- with .Values.dnsConfig }}
  dnsConfig:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .Values.hostAliases }}
  hostAliases:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .Values.readinessGates }}
  readinessGates:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  terminationGracePeriodSeconds: {{ .Values.terminationGracePeriodSeconds }}
  {{- with .Values.podSecurityContext }}
  securityContext:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .Values.nodeSelector }}
  nodeSelector:
    {{- tpl (toYaml .) $root | nindent 4 }}
  {{- end }}
  {{- with .Values.tolerations }}
  tolerations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with (include "generic.affinity" . | trim) }}{{ . | nindent 2 }}{{ end }}
  {{- with (include "generic.topologySpreadConstraints" . | trim) }}{{ . | nindent 2 }}{{ end }}
  {{- with .Values.initContainers }}
  initContainers:
    {{- tpl (toYaml .) $root | nindent 4 }}
  {{- end }}
  containers:
    - name: {{ .Values.containerName | default (include "generic.name" .) }}
      image: {{ include "generic.image" . | quote }}
      imagePullPolicy: {{ .Values.image.pullPolicy }}
      {{- with .Values.command }}
      command:
        {{- tpl (toYaml .) $root | nindent 8 }}
      {{- end }}
      {{- with .Values.args }}
      args:
        {{- tpl (toYaml .) $root | nindent 8 }}
      {{- end }}
      {{- with .Values.workingDir }}
      workingDir: {{ . }}
      {{- end }}
      {{- with .Values.ports }}
      ports:
        {{- range . }}
        - name: {{ .name }}
          containerPort: {{ .containerPort }}
          protocol: {{ .protocol | default "TCP" }}
          {{- with .hostPort }}
          hostPort: {{ . }}
          {{- end }}
        {{- end }}
      {{- end }}
      {{- with (include "generic.env" . | trim) }}
      env:
        {{- . | nindent 8 }}
      {{- end }}
      {{- with (include "generic.envFrom" . | trim) }}
      envFrom:
        {{- . | nindent 8 }}
      {{- end }}
      {{- with .Values.startupProbe }}
      startupProbe:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.livenessProbe }}
      livenessProbe:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.readinessProbe }}
      readinessProbe:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.lifecycle }}
      lifecycle:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.resources }}
      resources:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.resizePolicy }}
      resizePolicy:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.securityContext }}
      securityContext:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with (include "generic.volumeMounts" . | trim) }}
      volumeMounts:
        {{- . | nindent 8 }}
      {{- end }}
    {{- with .Values.sidecars }}
    {{- tpl (toYaml .) $root | nindent 4 }}
    {{- end }}
  {{- with (include "generic.volumes" . | trim) }}
  volumes:
    {{- . | nindent 4 }}
  {{- end }}
{{- end }}
