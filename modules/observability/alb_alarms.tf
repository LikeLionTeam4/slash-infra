# rds_alarms.tf가 미뤄뒀던 ALB 5xx 알람 — ALB Ingress가 실제로 떠서(dev, api.dev.sbsh.cloud)
# alb_arn_suffix를 넘겨줄 수 있게 되면 생성한다. count로 옵션 처리하는 이유는 아직 ALB가
# 없는 환경(local 등)에서 이 모듈을 그대로 재사용해도 에러 없이 넘어가야 해서다.

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  count = var.alb_arn_suffix == null ? 0 : 1

  alarm_name          = "${var.name_prefix}-alb-5xx-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  period              = 300
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  statistic           = "Sum"
  threshold           = var.alb_5xx_threshold_count
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "alb_target_response_time" {
  count = var.alb_arn_suffix == null ? 0 : 1

  alarm_name          = "${var.name_prefix}-alb-latency-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  period              = 300
  namespace           = "AWS/ApplicationELB"
  metric_name         = "TargetResponseTime"
  statistic           = "Average"
  threshold           = var.alb_target_response_time_threshold_seconds
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = var.tags
}
