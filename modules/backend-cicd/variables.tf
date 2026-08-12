variable "name_prefix" {
  description = "리소스명 접두사"
  type        = string
  default     = "slash"
}

variable "service" {
  description = "서비스 이름 (api / nlu / llm) — Role 이름과 태그에 사용"
  type        = string
}

variable "github_repo" {
  description = "GitHub Actions가 이 Role을 assume할 수 있는 저장소 (owner/repo 형식, 예: LikeLionTeam4/slash-api)"
  type        = string
}

variable "github_branches" {
  description = "이 브랜치들에서 실행되는 워크플로만 Role을 assume할 수 있다 (dev/main 둘 다 신뢰 — §9-3 배포 전략)"
  type        = list(string)
  default     = ["dev", "main"]
}

variable "ecr_repository_arn" {
  description = "modules/ecr output의 repository_arns[service] — 이 리포지토리에만 push 권한을 준다"
  type        = string
}

variable "tags" {
  description = "모든 리소스에 붙일 공통 태그"
  type        = map(string)
  default     = {}
}
