output "sns_topic_arn" {
  value = aws_sns_topic.alarms.arn
}

output "dashboard_url" {
  description = "팀원이 바로 열어볼 수 있는 CloudWatch 대시보드 콘솔 링크"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.dev.dashboard_name}"
}
