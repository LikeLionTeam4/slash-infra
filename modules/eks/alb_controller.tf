# AWS Load Balancer Controller용 IRSA Role만 미리 준비한다. 컨트롤러 자체(Helm 설치)는
# karpenter.tf와 같은 이유로 K8s 내부 리소스라 GitOps로 별도 설치.
#
# 정책 문서(alb_controller_iam_policy.json)는 손으로 옮기지 않고 AWS 공식 배포본
# (kubernetes-sigs/aws-load-balancer-controller docs/install/iam_policy.json)을 그대로
# 받아서 파일로 둔다 — 나중에 컨트롤러 버전을 올릴 때 diff로 갱신 여부를 바로 확인하기 위함.

locals {
  alb_controller_service_account = "system:serviceaccount:kube-system:aws-load-balancer-controller"
}

data "aws_iam_policy_document" "alb_controller_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url_no_prefix}:sub"
      values   = [local.alb_controller_service_account]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url_no_prefix}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "alb_controller" {
  name               = "${var.name_prefix}-alb-controller-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.alb_controller_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "alb_controller" {
  name   = "${var.name_prefix}-alb-controller-${var.environment}"
  role   = aws_iam_role.alb_controller.id
  policy = file("${path.module}/alb_controller_iam_policy.json")
}
