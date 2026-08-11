{{- define "slash-llm.fullname" -}}
slash-llm
{{- end -}}

{{- define "slash-llm.labels" -}}
app.kubernetes.io/name: slash-llm
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "slash-llm.selectorLabels" -}}
app.kubernetes.io/name: slash-llm
{{- end -}}
