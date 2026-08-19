# 문서(§10)가 "최소한 먼저" 붙이라고 한 핵심 알람 중 RDS 2개. ALB 5xx/레이턴시는
# ALB Ingress가 실제로 뜬 뒤 alb_alarms.tf로, Valkey는 valkey_alarms.tf로 각각 추가됨
# (2026-08-19). GPU 노드 사용률은 GPU 노드그룹 자체가 아직 없어서(llm-runtime은 별도
# EC2 방식) 그게 생기면 추가한다.

resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "${var.name_prefix}-rds-cpu-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  period              = 300
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  threshold           = var.rds_cpu_threshold_percent

  dimensions = {
    DBInstanceIdentifier = var.rds_instance_id
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "rds_free_storage" {
  alarm_name          = "${var.name_prefix}-rds-free-storage-${var.environment}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  period              = 300
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  statistic           = "Average"
  threshold           = var.rds_free_storage_threshold_bytes

  dimensions = {
    DBInstanceIdentifier = var.rds_instance_id
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = var.tags
}
