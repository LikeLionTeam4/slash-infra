# 서비스별 컨테이너 이미지 리포지토리 (문서 §6). 이미지 태그는 커밋 SHA 기준이라
# 같은 태그를 덮어쓸 일이 없으므로 IMMUTABLE로 막아둔다.
#
# local/dev/prod가 같은 이미지(sha- 태그, 계정 공용)를 승격해가며 쓰는 구조라
# 환경별 모듈(modules/eks)이 아니라 bootstrap에서 계정당 한 번만 만든다
# (2026-08-12, state 버킷·Route53 zone과 같은 이유 — docs/aws-architecture.md §6 참고).

locals {
  ecr_repositories = ["slash-api", "slash-nlu", "slash-llm"]
}

resource "aws_ecr_repository" "services" {
  for_each = toset(local.ecr_repositories)

  name                 = each.value
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(var.tags, {
    Name = each.value
  })
}

resource "aws_ecr_lifecycle_policy" "services" {
  for_each = aws_ecr_repository.services

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "태그 없는 이미지는 7일 후 정리"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "태그 있는 이미지는 최근 10개만 유지"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["sha-"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = { type = "expire" }
      }
    ]
  })
}
