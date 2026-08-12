# GitHub Actions가 aws-actions/configure-aws-credentials로 임시 자격증명을 받아
# 해당 서비스의 ECR 리포지토리에만 이미지를 push할 수 있게 하는 Role.
#
# modules/frontend-cicd와 달리 환경(dev/prod) 접미사를 붙이지 않는다 — ECR이 계정
# 공용 리소스라(§6) dev/main 어느 브랜치에서 push하든 같은 리포지토리, 같은 권한이면
# 충분해서, Role 하나가 여러 브랜치를 동시에 신뢰한다(github_branches).
#
# OIDC provider는 frontend-cicd와 동일하게 이미 계정에 있는 것을 읽기 전용 참조만 한다.

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

    # StringLike + 와일드카드를 쓰는 이유는 modules/frontend-cicd와 동일 — LikeLionTeam4
    # 조직의 GitHub OIDC "immutable IDs"가 sub 클레임에 숫자 ID를 붙여서 보낸다
    # (docs/operations-log.md §4 참고).
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        for branch in var.github_branches :
        "repo:${split("/", var.github_repo)[0]}*/${split("/", var.github_repo)[1]}*:ref:refs/heads/${branch}"
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecr_push" {
  name               = "${var.name_prefix}-${var.service}-cicd"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "ecr_push_permissions" {
  statement {
    sid = "EcrAuth"
    # GetAuthorizationToken은 리소스 스코핑 자체가 불가능한 액션이다(AWS 문서에 명시)
    # — docker login에 필요한 최소 권한.
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "EcrPush"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
    ]
    resources = [var.ecr_repository_arn]
  }
}

resource "aws_iam_role_policy" "ecr_push" {
  name   = "${var.name_prefix}-${var.service}-cicd"
  role   = aws_iam_role.ecr_push.id
  policy = data.aws_iam_policy_document.ecr_push_permissions.json
}
