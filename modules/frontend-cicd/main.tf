# GitHub Actions가 aws-actions/configure-aws-credentials로 임시 자격증명을 받아
# S3 sync + CloudFront invalidation만 수행할 수 있게 하는 배포 전용 Role.
#
# OIDC provider(token.actions.githubusercontent.com)는 이 계정에 이미 존재한다 —
# 이 부트캠프 계정을 여러 팀이 공유하고 있고, IAM OIDC provider는 계정에 URL당
# 1개만 등록 가능해서 우리가 새로 만들 수도, 만들어서도 안 된다. data source로
# 읽기 전용 참조만 하고, 이 모듈은 그 provider의 생명주기에 전혀 관여하지 않는다.

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    # StringEquals가 아니라 StringLike + 와일드카드를 쓴다. LikeLionTeam4 조직은
    # GitHub의 OIDC "immutable IDs"가 켜져 있어서 실제 sub 클레임이
    # "repo:LikeLionTeam4/slash-web:ref:refs/heads/dev"가 아니라
    # "repo:LikeLionTeam4@305683394/slash-web@1315812460:ref:refs/heads/dev"처럼
    # 조직/저장소명 뒤에 불변 숫자 ID가 붙어서 온다(2026-08-05 CloudTrail로 확인,
    # docs/operations-log.md §4 참고). 숫자 ID를 하드코딩하면 재사용성이 떨어지고
    # 깨지기 쉬워서, ID가 붙어도/안 붙어도 매칭되도록 각 이름 뒤에 와일드카드를 둔다.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${split("/", var.github_repo)[0]}*/${split("/", var.github_repo)[1]}*:ref:refs/heads/${var.github_branch}"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "deploy" {
  name               = "${var.name_prefix}-frontend-deploy-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "deploy_permissions" {
  statement {
    sid = "S3Sync"
    actions = [
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
    ]
    resources = [
      var.bucket_arn,
      "${var.bucket_arn}/*",
    ]
  }

  statement {
    sid       = "CloudFrontInvalidation"
    actions   = ["cloudfront:CreateInvalidation"]
    resources = [var.cloudfront_distribution_arn]
  }
}

resource "aws_iam_role_policy" "deploy" {
  name   = "${var.name_prefix}-frontend-deploy-${var.environment}"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.deploy_permissions.json
}
