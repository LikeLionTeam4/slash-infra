{{- define "slash-nlu.fullname" -}}
slash-nlu
{{- end -}}

{{- define "slash-nlu.labels" -}}
app.kubernetes.io/name: slash-nlu
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "slash-nlu.selectorLabels" -}}
app.kubernetes.io/name: slash-nlu
{{- end -}}
