variable "bucket_name" {
  description = "S3 버킷 이름의 접두사. 실제 버킷 이름은 여기에 AWS 계정ID가 자동으로 붙는다 (예: slash-web-local-123456789012) — 계정마다 자동으로 달라지므로 팀원끼리 겹칠 걱정 없이 기본값을 그대로 써도 된다."
  type        = string
  default     = "slash-web-local"
}

variable "domain_name" {
  description = "이 환경에 붙일 커스텀 도메인 (예: dev.slash.app)"
  type        = string
}

variable "hosted_zone_id" {
  description = "domain_name이 속한 Route53 호스팅 존 ID"
  type        = string
}
