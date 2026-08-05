variable "name_prefix" {
  description = "리소스명 접두사"
  type        = string
  default     = "slash"
}

variable "environment" {
  description = "환경 이름 (local / dev / prod 등) — 리소스명과 Environment 태그에 사용"
  type        = string
}

variable "bucket_arn" {
  description = "modules/frontend-hosting output의 bucket_arn — 이 버킷에만 배포 권한을 준다"
  type        = string
}

variable "cloudfront_distribution_arn" {
  description = "modules/frontend-hosting output의 cloudfront_distribution_arn — 이 배포에만 invalidation 권한을 준다"
  type        = string
}

variable "github_repo" {
  description = "GitHub Actions가 이 Role을 assume할 수 있는 저장소 (owner/repo 형식, 예: LikeLionTeam4/slash-web)"
  type        = string
}

variable "github_branch" {
  description = "이 브랜치에서 실행되는 워크플로만 Role을 assume할 수 있다"
  type        = string
  default     = "main"
}

variable "tags" {
  description = "모든 리소스에 붙일 공통 태그"
  type        = map(string)
  default     = {}
}
