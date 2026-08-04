variable "rds_instance_id" {
  description = "environments/local/database output의 rds_instance_id"
  type        = string
}

variable "alarm_email" {
  description = "알람 이메일 (선택 — 없으면 SNS 토픽만 만들고 구독은 나중에 콘솔에서 추가)"
  type        = string
  default     = null
}
