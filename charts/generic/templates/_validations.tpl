{{/*
Fail fast on invalid combinations. Called from workload.yaml.
*/}}
{{- define "generic.validate" -}}
{{- $kind := .Values.workload.kind -}}
{{- if not (has $kind (list "Deployment" "StatefulSet" "DaemonSet")) -}}
{{- fail (printf "workload.kind must be Deployment, StatefulSet or DaemonSet (got %q)" $kind) -}}
{{- end -}}
{{- if and .Values.autoscaling.enabled .Values.keda.enabled -}}
{{- fail "autoscaling.enabled and keda.enabled are mutually exclusive (KEDA creates its own HPA)" -}}
{{- end -}}
{{- if and (eq $kind "DaemonSet") (or .Values.autoscaling.enabled .Values.keda.enabled) -}}
{{- fail "autoscaling/keda cannot target a DaemonSet" -}}
{{- end -}}
{{- if and (eq $kind "DaemonSet") .Values.persistence.enabled (not .Values.persistence.existingClaim) -}}
{{- fail "persistence on a DaemonSet requires persistence.existingClaim (usually RWX); use extraVolumes with hostPath for node-local data" -}}
{{- end -}}
{{- range $k := (keys (.Values.secrets | default dict)) -}}
{{- if hasKey ($.Values.externalSecrets | default dict) $k -}}
{{- fail (printf "secrets.%s and externalSecrets.%s would both create Secret <fullname>-%s — rename one" $k $k $k) -}}
{{- end -}}
{{- end -}}
{{- if and (or .Values.ingress.enabled .Values.httpRoute.enabled .Values.grpcRoute.enabled .Values.serviceMonitor.enabled) (not (include "generic.serviceEnabled" .)) -}}
{{- fail "ingress/httpRoute/grpcRoute/serviceMonitor need the Service: set service.enabled=true and at least one exposed port" -}}
{{- end -}}
{{- if and .Values.image.tag (not (kindIs "string" .Values.image.tag)) -}}
{{- fail "image.tag must be a string — quote it (e.g. tag: \"1.0\")" -}}
{{- end -}}
{{- range .Values.ports -}}
{{- if or (not .name) (not .containerPort) -}}
{{- fail "every entry in ports needs name and containerPort" -}}
{{- end -}}
{{- end -}}
{{- end }}
