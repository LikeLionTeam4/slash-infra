output "repository_urls" {
  value = { for name, repo in aws_ecr_repository.services : name => repo.repository_url }
}

output "repository_arns" {
  description = "백엔드 CI Role의 ECR push 권한을 리포지토리 단위로 좁히는 데 쓴다 (modules/backend-cicd)"
  value       = { for name, repo in aws_ecr_repository.services : name => repo.arn }
}
