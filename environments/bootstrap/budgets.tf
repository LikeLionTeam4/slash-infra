# 계정 전체 지출에 대한 자동 경고 장치. CloudWatch 알람(modules/observability)은 RDS
# CPU/스토리지처럼 특정 환경의 특정 리소스만 보는데, 이건 그 반대 — 어떤 리소스가
# 원인이든 계정 전체 월 지출이 예산을 넘으면 알려준다. 계정 공용 자원이라 ECR/CI Role과
# 같은 이유로 bootstrap이 소유한다(§6, §9-3).
#
# 임계값 갱신(2026-08-18, 이슈 5): dev 상시운영 전환 후 사용자와 함께 실측 스펙 기준
# 재산정 — EKS/RDS(Multi-AZ)/Valkey/NAT 2개 baseline이 이미 월 ~$380~390, 여기에
# Ollama GPU EC2(Spot+평일 09~21시 스케줄, modules/llm-runtime/schedule.tf)를 더하면
# 월 ~$440~475로 추정된다. 예전 $100은 local/dev를 apply→destroy로 짧게 돌리던
# 시절 기준값이라 상시운영 baseline만으로도 이미 초과 — $500으로 상향, 변동비(NAT
# 데이터 처리, 다른 팀원의 local 실험 등) 여유를 감안했다. prod가 생기면 다시 재산정.
#
# 후속(같은 날 오후, PR #36): Ollama EC2가 Spot 용량 부족으로 On-Demand로 재전환되며
# GPU 비용이 월 ~$60~85 -> ~$170로 올라 실제 baseline은 위 추정(~$440~475)보다 높다
# (~$550~560 안팎 추정) — $500 한도를 넘을 수 있다. 한도는 이번엔 다시 안 건드림
# (docs/operations-log.md §11-5, 비용 재산정은 낮은 우선순위로 보류 확인).

resource "aws_budgets_budget" "monthly_cost" {
  name         = "slash-monthly-cost"
  budget_type  = "COST"
  limit_amount = "500"
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
