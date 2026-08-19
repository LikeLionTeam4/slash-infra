# 이슈 #44 "dev 상태 대시보드" 항목만 처리. EKS 컨트롤플레인/파드 로그는 별도 결정 사항이라
# 이 대시보드에 포함하지 않는다 — EKS는 Container Insights 없이는 CloudWatch에 기본 지표를
# 아예 내보내지 않기 때문에(RDS/ALB/ElastiCache와 달리 자동 발행이 아님), 지금 위젯으로 만들어도
# 빈 그래프만 뜬다. Container Insights 도입 여부가 결정되면 그때 위젯을 추가한다.
#
# 위젯마다 metrics를 직접 나열하지 않고 annotations.alarms로 기존 알람 ARN을 참조한다 —
# rds_alarms.tf/alb_alarms.tf/valkey_alarms.tf에 이미 namespace/metric/dimension이 정의돼
# 있으니 여기서 중복 선언하지 않아도 되고, 임계값 변경이 알람 쪽 한 곳만 고치면 대시보드에도
# 자동 반영된다. ALB/Valkey는 알람과 마찬가지로 대상이 없는 환경(local 등)에서는 위젯도 생기지 않는다.

locals {
  dashboard_widget_alarms = concat(
    [aws_cloudwatch_metric_alarm.rds_cpu.arn, aws_cloudwatch_metric_alarm.rds_free_storage.arn],
    var.alb_arn_suffix == null ? [] : [
      aws_cloudwatch_metric_alarm.alb_5xx[0].arn,
      aws_cloudwatch_metric_alarm.alb_target_response_time[0].arn,
    ],
    var.valkey_cache_cluster_id == null ? [] : [
      aws_cloudwatch_metric_alarm.valkey_cpu[0].arn,
      aws_cloudwatch_metric_alarm.valkey_memory[0].arn,
      aws_cloudwatch_metric_alarm.valkey_evictions[0].arn,
    ],
  )

  dashboard_widget_titles = concat(
    ["RDS CPU", "RDS Free Storage"],
    var.alb_arn_suffix == null ? [] : ["ALB 5xx", "ALB Target Response Time"],
    var.valkey_cache_cluster_id == null ? [] : ["Valkey CPU", "Valkey Memory", "Valkey Evictions"],
  )

  dashboard_widgets = [
    for idx, arn in local.dashboard_widget_alarms : {
      type   = "metric"
      x      = (idx % 2) * 12
      y      = floor(idx / 2) * 6
      width  = 12
      height = 6
      properties = {
        title   = local.dashboard_widget_titles[idx]
        view    = "timeSeries"
        region  = var.aws_region
        stacked = false
        annotations = {
          alarms = [arn]
        }
      }
    }
  ]
}

resource "aws_cloudwatch_dashboard" "dev" {
  dashboard_name = "${var.name_prefix}-dashboard-${var.environment}"

  dashboard_body = jsonencode({
    widgets = local.dashboard_widgets
  })
}
