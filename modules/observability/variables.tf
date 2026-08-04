variable "name_prefix" {
  description = "리소스명 접두사"
  type        = string
  default     = "slash"
}

variable "environment" {
  description = "환경 이름 (local / dev / prod 등) — 리소스명과 Environment 태그에 사용"
  type        = string
}

variable "rds_instance_id" {
  description = "database 모듈의 rds_instance_id output — CPU/스토리지 알람이 감시할 대상"
  type        = string
}

variable "rds_cpu_threshold_percent" {
  type    = number
  default = 80
}

variable "rds_free_storage_threshold_bytes" {
  description = "이 값 밑으로 떨어지면 알람 (기본 2GB)"
  type        = number
  default     = 2147483648
}

variable "alarm_email" {
  description = "알람 알림 받을 이메일. null이면 SNS 구독 없이 토픽만 만든다 (나중에 콘솔/CLI로 구독 추가 가능)"
  type        = string
  default     = null
}

variable "tags" {
  description = "모든 리소스에 붙일 공통 태그"
  type        = map(string)
  default     = {}
}
