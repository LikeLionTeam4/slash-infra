# Fluent Bit(aws-for-fluent-bit)용 IRSA Role만 미리 준비한다. 컨트롤러 자체(Helm 설치)는
# karpenter.tf/alb_controller.tf와 같은 이유로 K8s 내부 리소스라 GitOps 대상이 아니고
# 별도 문서(slash-infra/logging/README.md)의 helm install로 직접 설치한다.
#
# 로그 그룹(aws_cloudwatch_log_group.application, logging.tf)은 Terraform이 보존기간을
# 명시해 미리 만들어두므로, Fluent Bit 쪽 권한에는 logs:CreateLogGroup/PutRetentionPolicy를
# 주지 않는다 — 차트 설정이 보존기간을 무기한으로 되돌리는 걸 원천 차단.

locals {
  fluent_bit_service_account = "system:serviceaccount:amazon-cloudwatch:fluent-bit"
}

data "aws_iam_policy_document" "fluent_bit_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url_no_prefix}:sub"
      values   = [local.fluent_bit_service_account]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url_no_prefix}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "fluent_bit" {
  name               = "${var.name_prefix}-fluent-bit-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.fluent_bit_assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "fluent_bit" {
  statement {
    sid = "WriteAppLogs"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]
    resources = ["${aws_cloudwatch_log_group.application.arn}:*"]
  }
}

resource "aws_iam_role_policy" "fluent_bit" {
  name   = "${var.name_prefix}-fluent-bit-${var.environment}"
  role   = aws_iam_role.fluent_bit.id
  policy = data.aws_iam_policy_document.fluent_bit.json
}
