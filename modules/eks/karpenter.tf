# Karpenter 컨트롤러용 IRSA Role만 미리 준비해둔다. Karpenter 자체(Helm 설치,
# NodePool/EC2NodeClass CRD)는 K8s 내부 리소스라 GitOps로 별도 관리 — 여기서는
# "나중에 Karpenter를 붙이면 바로 쓸 수 있는 Role"까지만 만든다.
#
# 컨트롤러가 시작할 노드에 붙일 인스턴스 프로필은 node_group.tf의
# aws_iam_instance_profile.node를 그대로 재사용한다 (범용 노드그룹과 동일한 권한이면 충분).

locals {
  karpenter_service_account = "system:serviceaccount:kube-system:karpenter"
  oidc_provider_url_no_prefix = replace(
    aws_iam_openid_connect_provider.eks.url, "https://", ""
  )
}

data "aws_iam_policy_document" "karpenter_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url_no_prefix}:sub"
      values   = [local.karpenter_service_account]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url_no_prefix}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "karpenter_controller" {
  name               = "${var.name_prefix}-karpenter-controller-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.karpenter_assume.json
  tags               = var.tags
}

# Karpenter 공식 문서가 요구하는 컨트롤러 정책(EC2 fleet 관리 + 노드 Role PassRole).
data "aws_iam_policy_document" "karpenter_controller" {
  statement {
    sid = "EC2FleetManagement"
    actions = [
      "ec2:CreateFleet",
      "ec2:CreateLaunchTemplate",
      "ec2:CreateTags",
      "ec2:DeleteLaunchTemplate",
      "ec2:RunInstances",
      "ec2:TerminateInstances",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeImages",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeInstanceTypeOfferings",
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSpotPriceHistory",
      "ec2:DescribeSubnets",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "PassNodeRole"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.node.arn]
  }

  statement {
    sid       = "EKSClusterRead"
    actions   = ["eks:DescribeCluster"]
    resources = [aws_eks_cluster.main.arn]
  }

  statement {
    sid       = "PricingRead"
    actions   = ["pricing:GetProducts", "ssm:GetParameter"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "karpenter_controller" {
  name   = "${var.name_prefix}-karpenter-controller-${var.environment}"
  role   = aws_iam_role.karpenter_controller.id
  policy = data.aws_iam_policy_document.karpenter_controller.json
}
