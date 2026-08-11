{{- define "slash-api.fullname" -}}
slash-api
{{- end -}}

{{- define "slash-api.labels" -}}
app.kubernetes.io/name: slash-api
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "slash-api.selectorLabels" -}}
app.kubernetes.io/name: slash-api
{{- end -}}
