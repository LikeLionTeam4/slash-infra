variable "bucket_name" {
  description = "정적 파일을 담을 S3 버킷 이름 (전역에서 고유해야 함)"
  type        = string
}

variable "domain_name" {
  description = "사이트에 붙일 커스텀 도메인 (예: slash.app, dev.slash.app)"
  type        = string
}

variable "hosted_zone_id" {
  description = "domain_name이 속한 Route53 호스팅 존 ID"
  type        = string
}

variable "price_class" {
  description = "CloudFront 가격 등급"
  type        = string
  default     = "PriceClass_200" # 한국 포함 아시아/유럽/북미 — All보다 저렴하면서 대상 지역은 커버
}

variable "tags" {
  description = "모든 리소스에 붙일 공통 태그"
  type        = map(string)
  default     = {}
}

variable "force_destroy" {
  description = "true면 버킷이 비어있지 않아도 destroy 가능 (안의 오브젝트 전부 같이 삭제). 여기 담기는 건 빌드 산출물이라 재생산 가능한 환경(local 등)에서만 true로 켠다 — 기본값은 안전하게 false."
  type        = bool
  default     = false
}
