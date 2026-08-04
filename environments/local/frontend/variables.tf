variable "bucket_name" {
  description = "정적 파일을 담을 S3 버킷 이름 (전역에서 고유해야 함)"
  type        = string
}

variable "domain_name" {
  description = "이 환경에 붙일 커스텀 도메인 (예: dev.slash.app)"
  type        = string
}

variable "hosted_zone_id" {
  description = "domain_name이 속한 Route53 호스팅 존 ID"
  type        = string
}
