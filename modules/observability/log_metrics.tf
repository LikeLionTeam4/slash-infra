# 로그를 tail/Insights 쿼리로만 보면 "지금 상태가 정상인지"를 한눈에 알기 어렵다는 피드백으로
# 추가(2026-08-27). 로그 그룹(application, modules/eks/fluent_bit_irsa.tf 참고)에서
# "ERROR"가 들어간 라인 수를 세는 metric filter를 만들어 시계열로 뽑아낸다 — Slack 붙이는
# 것도 아니고 새 인프라(Grafana/Loki)를 세우는 것도 아니라, 이미 있는 CloudWatch 무료
# 대시보드에 위젯만 얹는 가장 가벼운 방법.
#
# 패턴이 단순 substring 매칭(JSON의 log 필드 안에 "ERROR" 포함)이라 완벽하지 않다 — 정상 로그
# 문장에 우연히 "error"라는 단어가 들어가면 오탐될 수 있다. 지금은 "에러가 튀는 시점"을
# 대략적으로 잡는 용도로 충분하다고 보고, 필요해지면 서비스별 로그 포맷에 맞는 정교한 패턴으로
# 교체할 것.

resource "aws_cloudwatch_log_metric_filter" "application_errors" {
  count = var.application_log_group_name == null ? 0 : 1

  name           = "${var.name_prefix}-app-error-count-${var.environment}"
  log_group_name = var.application_log_group_name
  pattern        = "{ $.log = \"*ERROR*\" }"

  metric_transformation {
    name          = "ApplicationErrorCount"
    namespace     = "Slash/ApplicationLogs"
    value         = "1"
    default_value = "0"
    unit          = "Count"
  }
}
