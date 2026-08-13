output "private_ip" {
  description = "helm/slash-llm/values-dev.yaml의 env.OLLAMA_URL(http://<이 값>:11434)에 채울 값"
  value       = aws_instance.ollama.private_ip
}

output "instance_id" {
  value = aws_instance.ollama.id
}
