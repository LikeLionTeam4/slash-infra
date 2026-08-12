# local/dev/prod가 계정을 공유하는 동안은 이미지도 계정 공용이라(같은 sha- 태그를
# dev에서 검증 후 prod로 그대로 승격, §9-3) 환경별 모듈이 아니라 여기서 한 번만 만든다.
# 2026-08-12에 modules/eks에서 이전 — 원래 local/eks가 소유하던 리소스라, dev/eks를
# 새로 apply하면 같은 이름으로 충돌했을 것.

module "ecr" {
  source = "../../modules/ecr"

  tags = merge(local.tags, { Service = "ecr" })
}
