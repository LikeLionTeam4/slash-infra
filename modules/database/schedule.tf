# RDS를 평일 업무시간(09~21시)에만 띄운다(2026-08-18, 09~21시 운영 검토 논의) —
# modules/llm-runtime/schedule.tf와 동일하게 Lambda 없이 EventBridge Scheduler가
# RDS API(StartDBInstance/StopDBInstance)를 직접 호출하는 universal target을 쓴다.
#
# 정지 중에도 스토리지 비용은 유지되고, AWS가 정지 7일 경과 시 강제로 재기동시키는
# 룰이 있는데 평일마다 09시에 시작되므로 이 룰에 걸릴 일은 없다.
# Valkey(ElastiCache)는 stop/start API 자체가 없어 이 스케줄 대상이 아니다.

data "aws_iam_policy_document" "rds_scheduler_assume" {
  count = var.schedule_enabled ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "rds_scheduler" {
  count = var.schedule_enabled ? 1 : 0

  name               = "${var.name_prefix}-rds-scheduler-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.rds_scheduler_assume[0].json
  tags               = var.tags
}

data "aws_iam_policy_document" "rds_scheduler_rds" {
  count = var.schedule_enabled ? 1 : 0

  statement {
    actions   = ["rds:StartDBInstance", "rds:StopDBInstance"]
    resources = [aws_db_instance.main.arn]
  }
}

resource "aws_iam_role_policy" "rds_scheduler_rds" {
  count = var.schedule_enabled ? 1 : 0

  name   = "${var.name_prefix}-rds-scheduler-${var.environment}"
  role   = aws_iam_role.rds_scheduler[0].id
  policy = data.aws_iam_policy_document.rds_scheduler_rds[0].json
}

resource "aws_scheduler_schedule" "rds_start" {
  count = var.schedule_enabled ? 1 : 0

  name       = "${var.name_prefix}-rds-start-${var.environment}"
  group_name = "default"

  schedule_expression          = var.schedule_start_cron
  schedule_expression_timezone = var.schedule_timezone

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:rds:startDBInstance"
    role_arn = aws_iam_role.rds_scheduler[0].arn

    # universal target은 RDS API 문서의 "DBInstanceIdentifier"가 아니라 서비스 내부
    # 모델의 "DbInstanceIdentifier"(소문자 b)를 요구한다 — 첫 apply 때 "missing field
    # DbInstanceIdentifier" 에러로 확인(2026-08-19, EKS의 PascalCase 요구와 같은 종류의 불일치).
    input = jsonencode({
      DbInstanceIdentifier = aws_db_instance.main.identifier
    })
  }
}

resource "aws_scheduler_schedule" "rds_stop" {
  count = var.schedule_enabled ? 1 : 0

  name       = "${var.name_prefix}-rds-stop-${var.environment}"
  group_name = "default"

  schedule_expression          = var.schedule_stop_cron
  schedule_expression_timezone = var.schedule_timezone

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:rds:stopDBInstance"
    role_arn = aws_iam_role.rds_scheduler[0].arn

    input = jsonencode({
      DbInstanceIdentifier = aws_db_instance.main.identifier
    })
  }
}
