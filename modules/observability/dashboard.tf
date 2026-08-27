# 이슈 #44 "dev 상태 대시보드" 항목만 처리. EKS 파드 CPU/메모리 등 리소스 지표는 여전히
# 대시보드에 없다 — Container Insights 없이는 EKS가 CloudWatch에 기본 지표를 아예 내보내지
# 않기 때문에(RDS/ALB/ElastiCache와 달리 자동 발행이 아님, 이슈 #47에서 도입 여부 검토 중),
# 지금 위젯으로 만들어도 빈 그래프만 뜬다. 다만 파드 로그(Fluent Bit) 자체는 2026-08-27부터
# 수집 중이라(이슈 #44) 그 수집량(IncomingBytes)/에러 카운트/최근 에러 로그 위젯 3개를
# 아래에 별도로 추가한다 — 로그를 tail/Insights 쿼리로만 보면 이해하기 어렵다는 피드백 반영,
# Prometheus/Grafana 같은 별도 스택 없이 지금 있는 CloudWatch 대시보드에만 얹는다.
#
# 알람 기반 위젯은 metrics를 직접 나열하지 않고 annotations.alarms로 기존 알람 ARN을 참조한다
# — rds_alarms.tf/alb_alarms.tf/valkey_alarms.tf에 이미 namespace/metric/dimension이 정의돼
# 있으니 여기서 중복 선언하지 않아도 되고, 임계값 변경이 알람 쪽 한 곳만 고치면 대시보드에도
# 자동 반영된다. ALB/Valkey는 알람과 마찬가지로 대상이 없는 환경(local 등)에서는 위젯도 생기지 않는다.
# 로그 관련 위젯 3개는 아직 임계값을 정하지 않아 알람이 없으므로(§26 실측 대기 중) 예외적으로
# metrics/query를 직접 선언하는 raw metric/log 위젯이다.

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

  # 로그 관련 위젯 3개(수집량/에러 카운트/최근 에러 로그)는 서로 properties 모양이 달라서
  # (metrics 키가 있는 것도, query 키가 있는 것도 있음) 하나의 리스트 리터럴로 만들면 Terraform이
  # 타입을 통일하지 못해 validate 에러가 난다 — 위젯마다 별도 local로 쪼개서 concat한다
  # (alarm 위젯 리스트 + 이 리스트들을 concat하는 것 자체는 문제없음, 그 안의 리스트 리터럴
  # 하나에 서로 다른 모양의 object를 여러 개 섞는 것만 문제).
  log_ingestion_widget = var.application_log_group_name == null ? [] : [
    {
      type   = "metric"
      x      = (length(local.dashboard_widget_alarms) % 2) * 12
      y      = floor(length(local.dashboard_widget_alarms) / 2) * 6
      width  = 12
      height = 6
      properties = {
        title   = "Application Log Ingestion (Fluent Bit)"
        view    = "timeSeries"
        region  = var.aws_region
        stacked = false
        metrics = [
          ["AWS/Logs", "IncomingBytes", "LogGroupName", var.application_log_group_name, { stat = "Sum", period = 3600 }]
        ]
      }
    }
  ]

  error_count_widget = var.application_log_group_name == null ? [] : [
    {
      type   = "metric"
      x      = ((length(local.dashboard_widget_alarms) + 1) % 2) * 12
      y      = floor((length(local.dashboard_widget_alarms) + 1) / 2) * 6
      width  = 12
      height = 6
      properties = {
        title   = "Application Error Count"
        view    = "timeSeries"
        region  = var.aws_region
        stacked = false
        metrics = [
          ["Slash/ApplicationLogs", "ApplicationErrorCount", { stat = "Sum", period = 300 }]
        ]
      }
    }
  ]

  error_log_widget = var.application_log_group_name == null ? [] : [
    {
      type   = "log"
      x      = ((length(local.dashboard_widget_alarms) + 2) % 2) * 12
      y      = floor((length(local.dashboard_widget_alarms) + 2) / 2) * 6
      width  = 12
      height = 6
      properties = {
        title  = "최근 에러 로그"
        region = var.aws_region
        view   = "table"
        query  = "SOURCE '${var.application_log_group_name}' | fields @timestamp, kubernetes.pod_name, log | filter log like /ERROR/ | sort @timestamp desc | limit 20"
      }
    }
  ]

  dashboard_widgets = concat(
    [
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
    ],
    local.log_ingestion_widget,
    local.error_count_widget,
    local.error_log_widget,
  )
}

resource "aws_cloudwatch_dashboard" "dev" {
  dashboard_name = "${var.name_prefix}-dashboard-${var.environment}"

  dashboard_body = jsonencode({
    widgets = local.dashboard_widgets
  })
}
