# slash-api가 RDS/Valkey Secrets Manager 시크릿을 읽기 위한 IRSA Role(이슈 #23/#24).
# alb_controller.tf/karpenter.tf와 같은 패턴이지만 대상은 kube-system 컨트롤러가 아니라
# 앱 네임스페이스의 ServiceAccount 하나 — External Secrets Operator의 SecretStore가
# 이 ServiceAccount 신원으로 assume해서 시크릿을 읽고, ESO 자체에는 별도 권한을 주지 않는다
# (컨트롤러 하나에 계정 전체 시크릿 읽기 권한을 몰아주지 않기 위함).
#
# secret_arns가 비어 있으면(DB/Valkey가 아직 없는 환경) Role 자체를 안 만든다 — local처럼
# RDS/Valkey를 안 띄우는 환경에서 빈 정책 문서로 apply 에러가 나는 걸 피하기 위함.

locals {
  slash_api_service_account = "system:serviceaccount:default:slash-api"
}

data "aws_iam_policy_document" "slash_api_assume" {
  count = length(var.slash_api_secret_arns) > 0 ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url_no_prefix}:sub"
      values   = [local.slash_api_service_account]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url_no_prefix}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "slash_api" {
  count = length(var.slash_api_secret_arns) > 0 ? 1 : 0

  name               = "${var.name_prefix}-slash-api-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.slash_api_assume[0].json
  tags               = var.tags
}

data "aws_iam_policy_document" "slash_api_secrets" {
  count = length(var.slash_api_secret_arns) > 0 ? 1 : 0

  statement {
    sid       = "ReadAppSecrets"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = var.slash_api_secret_arns
  }
}

resource "aws_iam_role_policy" "slash_api_secrets" {
  count = length(var.slash_api_secret_arns) > 0 ? 1 : 0

  name   = "${var.name_prefix}-slash-api-secrets-${var.environment}"
  role   = aws_iam_role.slash_api[0].id
  policy = data.aws_iam_policy_document.slash_api_secrets[0].json
}
