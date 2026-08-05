output "role_arn" {
  description = "GitHub Actions 워크플로의 aws-actions/configure-aws-credentials가 assume할 Role ARN"
  value       = aws_iam_role.deploy.arn
}
