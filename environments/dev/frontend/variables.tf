variable "bucket_name" {
  description = "S3 버킷 이름의 접두사. 실제 버킷 이름은 여기에 AWS 계정ID가 자동으로 붙는다."
  type        = string
  default     = "slash-web-dev"
}

variable "domain_name" {
  description = "이 환경에 붙일 커스텀 도메인"
  type        = string
  default     = "dev.sbsh.cloud"
}

variable "hosted_zone_id" {
  description = "domain_name이 속한 Route53 호스팅 존 ID — environments/bootstrap output.route53_zone_id"
  type        = string
  default     = "Z02458772F0ED1QG30X6D"
}
