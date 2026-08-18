# Ollama EC2를 평일 업무시간에만 켜둔다(2026-08-18 비용 재검토) — Lambda 없이
# EventBridge Scheduler가 EC2 API(StartInstances/StopInstances)를 직접 호출하는
# "universal target"을 쓴다. 별도 컴포넌트(Lambda 코드·배포)를 늘리지 않기 위한 선택
# — S3 단독 state lock, 서비스 저장소 CI가 직접 커밋하는 태그 반영과 같은 방향.

data "aws_iam_policy_document" "scheduler_assume" {
  count = var.schedule_enabled ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ollama_scheduler" {
  count = var.schedule_enabled ? 1 : 0

  name               = "${var.name_prefix}-ollama-scheduler-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume[0].json
  tags               = var.tags
}

data "aws_iam_policy_document" "ollama_scheduler_ec2" {
  count = var.schedule_enabled ? 1 : 0

  statement {
    actions   = ["ec2:StartInstances", "ec2:StopInstances"]
    resources = [aws_instance.ollama.arn]
  }
}

resource "aws_iam_role_policy" "ollama_scheduler_ec2" {
  count = var.schedule_enabled ? 1 : 0

  name   = "${var.name_prefix}-ollama-scheduler-${var.environment}"
  role   = aws_iam_role.ollama_scheduler[0].id
  policy = data.aws_iam_policy_document.ollama_scheduler_ec2[0].json
}

resource "aws_scheduler_schedule" "ollama_start" {
  count = var.schedule_enabled ? 1 : 0

  name       = "${var.name_prefix}-ollama-start-${var.environment}"
  group_name = "default"

  schedule_expression          = var.schedule_start_cron
  schedule_expression_timezone = var.schedule_timezone

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:ec2:startInstances"
    role_arn = aws_iam_role.ollama_scheduler[0].arn

    input = jsonencode({
      InstanceIds = [aws_instance.ollama.id]
    })
  }
}

resource "aws_scheduler_schedule" "ollama_stop" {
  count = var.schedule_enabled ? 1 : 0

  name       = "${var.name_prefix}-ollama-stop-${var.environment}"
  group_name = "default"

  schedule_expression          = var.schedule_stop_cron
  schedule_expression_timezone = var.schedule_timezone

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:ec2:stopInstances"
    role_arn = aws_iam_role.ollama_scheduler[0].arn

    input = jsonencode({
      InstanceIds = [aws_instance.ollama.id]
    })
  }
}
