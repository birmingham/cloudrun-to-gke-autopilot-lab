{{- define "hello-api.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "hello-api.labels" -}}
{{ include "hello-api.selectorLabels" . }}
app.kubernetes.io/version: {{ .Values.image.tag | quote }}
{{- end }}
