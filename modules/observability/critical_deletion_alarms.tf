# NAT Gateway 삭제 사고(2026-08-21, 공유 계정의 다른 팀이 실수로 slash NAT 2개 삭제 —
# slash-infra#56, operations-log.md §19)를 계기로 추가. CloudWatch 알람은 메트릭 기반이라
# "리소스가 통째로 사라짐" 자체는 감지하기 어렵다 — 대신 이미 켜져 있는 CloudTrail(slash-trail)의
# 관리 이벤트를 EventBridge 기본 버스가 실시간으로 받는 것을 이용해, operations-log.md §2에
# "상시 유지"로 문서화된 리소스의 Delete* API 호출을 곧바로 SNS(이메일)로 보낸다.
#
# NAT Gateway/로드밸런서는 재생성될 때마다 ID가 바뀌어 특정 ID로 미리 걸어둘 수 없다 — 계정이
# 부트캠프 공유 계정이라 이 두 알림은 "다른 팀이 자기 NAT/ALB를 지운 것"도 함께 잡을 수 있다.
# 오탐(다른 팀 것도 알림)보다 놓치는 쪽(우리 것이 지워졌는데 못 알아채는 것)이 훨씬 비싸다고
# 판단해 계정 전체 이벤트를 그대로 받는 쪽을 택했다. EKS 클러스터/Cognito User Pool/Valkey는
# 이름·ID가 고정이라 requestParameters로 slash 것만 정확히 걸러낸다.

resource "aws_cloudwatch_event_rule" "nat_gateway_deleted" {
  name        = "${var.name_prefix}-nat-deleted-${var.environment}"
  description = "NAT Gateway 삭제(DeleteNatGateway) 감지 — 계정 전체(다른 팀 리소스 포함)"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventName = ["DeleteNatGateway"]
    }
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "nat_gateway_deleted" {
  rule = aws_cloudwatch_event_rule.nat_gateway_deleted.name
  arn  = aws_sns_topic.alarms.arn

  input_transformer {
    input_paths = {
      actor = "$.detail.userIdentity.arn"
      time  = "$.detail.eventTime"
      natId = "$.detail.requestParameters.DeleteNatGatewayRequest.NatGatewayId"
    }
    input_template = "\"[slash-dev] NAT Gateway 삭제됨: <natId> — 실행자: <actor>, 시각: <time> UTC. 우리(slash-vpc-dev) 리소스인지 'aws ec2 describe-nat-gateways'로 바로 확인하세요.\""
  }
}

resource "aws_cloudwatch_event_rule" "alb_deleted" {
  name        = "${var.name_prefix}-alb-deleted-${var.environment}"
  description = "로드밸런서 삭제(DeleteLoadBalancer) 감지 — 계정 전체(다른 팀 리소스 포함)"

  event_pattern = jsonencode({
    source      = ["aws.elasticloadbalancing"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventName = ["DeleteLoadBalancer"]
    }
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "alb_deleted" {
  rule = aws_cloudwatch_event_rule.alb_deleted.name
  arn  = aws_sns_topic.alarms.arn

  input_transformer {
    input_paths = {
      actor = "$.detail.userIdentity.arn"
      time  = "$.detail.eventTime"
      lbArn = "$.detail.requestParameters.loadBalancerArn"
    }
    input_template = "\"[slash-dev] 로드밸런서 삭제됨: <lbArn> — 실행자: <actor>, 시각: <time> UTC.\""
  }
}

resource "aws_cloudwatch_event_rule" "eks_cluster_deleted" {
  count = var.eks_cluster_name == null ? 0 : 1

  name        = "${var.name_prefix}-eks-cluster-deleted-${var.environment}"
  description = "EKS 클러스터 삭제(DeleteCluster) 감지 — ${var.eks_cluster_name}만"

  event_pattern = jsonencode({
    source      = ["aws.eks"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventName = ["DeleteCluster"]
      requestParameters = {
        name = [var.eks_cluster_name]
      }
    }
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "eks_cluster_deleted" {
  count = var.eks_cluster_name == null ? 0 : 1

  rule = aws_cloudwatch_event_rule.eks_cluster_deleted[0].name
  arn  = aws_sns_topic.alarms.arn

  input_transformer {
    input_paths = {
      actor = "$.detail.userIdentity.arn"
      time  = "$.detail.eventTime"
    }
    input_template = "\"[slash-dev] EKS 클러스터(${var.eks_cluster_name}) 삭제됨 — 실행자: <actor>, 시각: <time> UTC.\""
  }
}

resource "aws_cloudwatch_event_rule" "eks_nodegroup_deleted" {
  count = var.eks_cluster_name == null ? 0 : 1

  name        = "${var.name_prefix}-eks-nodegroup-deleted-${var.environment}"
  description = "EKS 노드그룹 삭제(DeleteNodegroup) 감지 — ${var.eks_cluster_name}만"

  event_pattern = jsonencode({
    source      = ["aws.eks"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventName = ["DeleteNodegroup"]
      requestParameters = {
        clusterName = [var.eks_cluster_name]
      }
    }
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "eks_nodegroup_deleted" {
  count = var.eks_cluster_name == null ? 0 : 1

  rule = aws_cloudwatch_event_rule.eks_nodegroup_deleted[0].name
  arn  = aws_sns_topic.alarms.arn

  input_transformer {
    input_paths = {
      actor     = "$.detail.userIdentity.arn"
      time      = "$.detail.eventTime"
      nodegroup = "$.detail.requestParameters.nodegroupName"
    }
    input_template = "\"[slash-dev] EKS 노드그룹(${var.eks_cluster_name}/<nodegroup>) 삭제됨 — 실행자: <actor>, 시각: <time> UTC. 09~21시 스케줄은 노드 수를 0으로 줄일 뿐 노드그룹 자체를 지우지 않으니, 이 알림이 오면 스케줄이 아니라 실수/의도적 삭제입니다.\""
  }
}

resource "aws_cloudwatch_event_rule" "cognito_pool_deleted" {
  count = var.cognito_user_pool_id == null ? 0 : 1

  name        = "${var.name_prefix}-cognito-pool-deleted-${var.environment}"
  description = "Cognito User Pool 삭제(DeleteUserPool) 감지 — ${var.cognito_user_pool_id}만"

  event_pattern = jsonencode({
    source      = ["aws.cognito-idp"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventName = ["DeleteUserPool"]
      requestParameters = {
        userPoolId = [var.cognito_user_pool_id]
      }
    }
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "cognito_pool_deleted" {
  count = var.cognito_user_pool_id == null ? 0 : 1

  rule = aws_cloudwatch_event_rule.cognito_pool_deleted[0].name
  arn  = aws_sns_topic.alarms.arn

  input_transformer {
    input_paths = {
      actor = "$.detail.userIdentity.arn"
      time  = "$.detail.eventTime"
    }
    input_template = "\"[slash-dev] Cognito User Pool(${var.cognito_user_pool_id}) 삭제됨 — 실행자: <actor>, 시각: <time> UTC. slash-web/slash-api 로그인이 즉시 끊깁니다.\""
  }
}

resource "aws_cloudwatch_event_rule" "valkey_deleted" {
  count = var.valkey_replication_group_id == null ? 0 : 1

  name        = "${var.name_prefix}-valkey-deleted-${var.environment}"
  description = "Valkey(ElastiCache) 삭제(DeleteReplicationGroup) 감지 — ${var.valkey_replication_group_id}만"

  event_pattern = jsonencode({
    source      = ["aws.elasticache"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventName = ["DeleteReplicationGroup"]
      requestParameters = {
        replicationGroupId = [var.valkey_replication_group_id]
      }
    }
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "valkey_deleted" {
  count = var.valkey_replication_group_id == null ? 0 : 1

  rule = aws_cloudwatch_event_rule.valkey_deleted[0].name
  arn  = aws_sns_topic.alarms.arn

  input_transformer {
    input_paths = {
      actor = "$.detail.userIdentity.arn"
      time  = "$.detail.eventTime"
    }
    input_template = "\"[slash-dev] Valkey(${var.valkey_replication_group_id}) 삭제됨 — 실행자: <actor>, 시각: <time> UTC.\""
  }
}
