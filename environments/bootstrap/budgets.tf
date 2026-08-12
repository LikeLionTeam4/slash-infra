# 계정 전체 지출에 대한 자동 경고 장치. CloudWatch 알람(modules/observability)은 RDS
# CPU/스토리지처럼 특정 환경의 특정 리소스만 보는데, 이건 그 반대 — 어떤 리소스가
# 원인이든 계정 전체 월 지출이 예산을 넘으면 알려준다. 계정 공용 자원이라 ECR/CI Role과
# 같은 이유로 bootstrap이 소유한다(§6, §9-3).
#
# 임계값(월 $100)은 확정치가 아니라 시작값 — local/dev를 apply→destroy로 짧게 돌리는
# 지금 사용 패턴 기준의 안전망이다. dev가 상시 운영으로 바뀌거나 prod가 생기면
# 실측 지출 보고 조정할 것.

resource "aws_budgets_budget" "monthly_cost" {
  name         = "slash-monthly-cost"
  budget_type  = "COST"
  limit_amount = "100"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name = "TagKeyValue"
    values = [
      "user:Project$slash",
    ]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.budget_alert_email]
  }
}
