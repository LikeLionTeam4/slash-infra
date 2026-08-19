# RDS는 처음부터 CPU/스토리지 알람이 있었는데 같은 database 모듈의 Valkey는 대칭이 안
# 맞았던 걸 메운다. valkey_cache_cluster_id가 없으면(local 등) 알람을 만들지 않는다.
#
# CPUUtilization 대신 EngineCPUUtilization을 쓰는 이유: ElastiCache 호스트의 CPUUtilization은
# 관리용 프로세스까지 포함해서 멀티코어 인스턴스에서는 실제 엔진 부하보다 낮게(코어 수로 나뉜 값처럼)
# 보일 수 있다는 게 AWS 공식 권고 — Redis/Valkey처럼 싱글스레드 엔진은 EngineCPUUtilization이
# 실제 부하를 더 정확히 반영한다.

resource "aws_cloudwatch_metric_alarm" "valkey_cpu" {
  count = var.valkey_cache_cluster_id == null ? 0 : 1

  alarm_name          = "${var.name_prefix}-valkey-cpu-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  period              = 300
  namespace           = "AWS/ElastiCache"
  metric_name         = "EngineCPUUtilization"
  statistic           = "Average"
  threshold           = var.valkey_cpu_threshold_percent

  dimensions = {
    CacheClusterId = var.valkey_cache_cluster_id
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "valkey_memory" {
  count = var.valkey_cache_cluster_id == null ? 0 : 1

  alarm_name          = "${var.name_prefix}-valkey-memory-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  period              = 300
  namespace           = "AWS/ElastiCache"
  metric_name         = "DatabaseMemoryUsagePercentage"
  statistic           = "Average"
  threshold           = var.valkey_memory_threshold_percent

  dimensions = {
    CacheClusterId = var.valkey_cache_cluster_id
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "valkey_evictions" {
  count = var.valkey_cache_cluster_id == null ? 0 : 1

  alarm_name          = "${var.name_prefix}-valkey-evictions-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  period              = 300
  namespace           = "AWS/ElastiCache"
  metric_name         = "Evictions"
  statistic           = "Sum"
  threshold           = var.valkey_evictions_threshold_count
  treat_missing_data  = "notBreaching"

  dimensions = {
    CacheClusterId = var.valkey_cache_cluster_id
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = var.tags
}
