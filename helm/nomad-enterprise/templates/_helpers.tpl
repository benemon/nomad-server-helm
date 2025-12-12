{{/*
Expand the name of the chart.
*/}}
{{- define "nomad.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "nomad.fullname" -}}
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
{{- define "nomad.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "nomad.labels" -}}
helm.sh/chart: {{ include "nomad.chart" . }}
{{ include "nomad.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.labels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "nomad.selectorLabels" -}}
app.kubernetes.io/name: {{ include "nomad.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app: nomad
component: server
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "nomad.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "nomad.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Namespace - uses standard Helm release namespace
*/}}
{{- define "nomad.namespace" -}}
{{- .Release.Namespace }}
{{- end }}

{{/*
Gossip key - use provided or generate new one
Lookup existing configmap to maintain gossip key across upgrades
*/}}
{{- define "nomad.gossipKey" -}}
{{- if .Values.gossip.key }}
{{- .Values.gossip.key }}
{{- else }}
{{- $configmap := lookup "v1" "ConfigMap" (include "nomad.namespace" .) (printf "%s-config" (include "nomad.fullname" .)) }}
{{- if $configmap }}
{{- $hcl := index $configmap.data "server.hcl" }}
{{- regexFind "encrypt = \"[^\"]+\"" $hcl | regexFind "[A-Za-z0-9+/=]{44,}" }}
{{- else }}
{{- randAlphaNum 32 | b64enc }}
{{- end }}
{{- end }}
{{- end }}
