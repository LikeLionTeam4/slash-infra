# 범용 노드그룹을 평일 업무시간(09~21시)에만 띄운다(2026-08-18, 09~21시 운영 검토 논의) —
# modules/llm-runtime/schedule.tf와 동일하게 Lambda 없이 EventBridge Scheduler가
# EKS API(UpdateNodegroupConfig)를 직접 호출하는 universal target을 쓴다.
#
# EKS 컨트롤플레인 자체는 stop 개념이 없어(삭제만 가능) 이 스케줄 대상이 아니다 —
# 컨트롤플레인 시간당 과금은 상시 유지되고, 이 스케줄은 범용 노드그룹 EC2 비용만 아낀다.

data "aws_iam_policy_document" "node_group_scheduler_assume" {
  count = var.schedule_enabled ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node_group_scheduler" {
  count = var.schedule_enabled ? 1 : 0

  name               = "${var.name_prefix}-eks-node-scheduler-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.node_group_scheduler_assume[0].json
  tags               = var.tags
}

data "aws_iam_policy_document" "node_group_scheduler_eks" {
  count = var.schedule_enabled ? 1 : 0

  statement {
    actions   = ["eks:UpdateNodegroupConfig"]
    resources = [aws_eks_node_group.general.arn]
  }
}

resource "aws_iam_role_policy" "node_group_scheduler_eks" {
  count = var.schedule_enabled ? 1 : 0

  name   = "${var.name_prefix}-eks-node-scheduler-${var.environment}"
  role   = aws_iam_role.node_group_scheduler[0].id
  policy = data.aws_iam_policy_document.node_group_scheduler_eks[0].json
}

resource "aws_scheduler_schedule" "node_group_start" {
  count = var.schedule_enabled ? 1 : 0

  name       = "${var.name_prefix}-eks-node-start-${var.environment}"
  group_name = "default"

  schedule_expression          = var.schedule_start_cron
  schedule_expression_timezone = var.schedule_timezone

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:eks:updateNodegroupConfig"
    role_arn = aws_iam_role.node_group_scheduler[0].arn

    # EKS universal target은 REST API 문서의 camelCase가 아니라 서비스 모델의
    # PascalCase 멤버명(ClusterName/NodegroupName/ScalingConfig...)을 요구한다 —
    # 첫 apply 때 "missing field ClusterName, NodegroupName" 에러로 확인(2026-08-19).
    input = jsonencode({
      ClusterName   = aws_eks_cluster.main.name
      NodegroupName = aws_eks_node_group.general.node_group_name
      ScalingConfig = {
        DesiredSize = var.node_desired_size
        MinSize     = var.node_min_size
        MaxSize     = var.node_max_size
      }
    })
  }
}

resource "aws_scheduler_schedule" "node_group_stop" {
  count = var.schedule_enabled ? 1 : 0

  name       = "${var.name_prefix}-eks-node-stop-${var.environment}"
  group_name = "default"

  schedule_expression          = var.schedule_stop_cron
  schedule_expression_timezone = var.schedule_timezone

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:eks:updateNodegroupConfig"
    role_arn = aws_iam_role.node_group_scheduler[0].arn

    input = jsonencode({
      ClusterName   = aws_eks_cluster.main.name
      NodegroupName = aws_eks_node_group.general.node_group_name
      ScalingConfig = {
        DesiredSize = 0
        MinSize     = 0
        MaxSize     = 0
      }
    })
  }
}
