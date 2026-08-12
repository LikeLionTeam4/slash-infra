# ECR과 같은 이유로 여기서 만든다 — 계정 공용 리소스(ECR)에 접근하는 Role이라
# 환경별 root가 아니라 그 리소스를 소유한 곳에 같이 둔다(§6, §9-3).

locals {
  backend_services = {
    api = "LikeLionTeam4/slash-api"
    nlu = "LikeLionTeam4/slash-nlu"
    llm = "LikeLionTeam4/slash-llm"
  }
}

module "backend_cicd" {
  for_each = local.backend_services
  source   = "../../modules/backend-cicd"

  service            = each.key
  github_repo        = each.value
  ecr_repository_arn = module.ecr.repository_arns["slash-${each.key}"]

  tags = merge(local.tags, { Service = "backend-cicd" })
}
