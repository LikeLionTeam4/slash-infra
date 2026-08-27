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

variable "alarm_emails" {
  description = "알람 알림 받을 이메일 목록. 빈 리스트면 SNS 구독 없이 토픽만 만든다 (나중에 콘솔/CLI로 구독 추가 가능)"
  type        = list(string)
  default     = []
}

variable "eks_cluster_name" {
  description = "이 이름의 EKS 클러스터가 삭제(DeleteCluster/DeleteNodegroup)되면 즉시 알림. null이면 알림을 만들지 않는다"
  type        = string
  default     = null
}

variable "cognito_user_pool_id" {
  description = "이 ID의 Cognito User Pool이 삭제(DeleteUserPool)되면 즉시 알림. null이면 알림을 만들지 않는다"
  type        = string
  default     = null
}

variable "valkey_replication_group_id" {
  description = "이 ID의 Valkey replication group이 삭제(DeleteReplicationGroup)되면 즉시 알림. null이면 알림을 만들지 않는다"
  type        = string
  default     = null
}

variable "alb_arn_suffix" {
  description = "ALB 5xx/레이턴시 알람이 감시할 대상(aws_lb의 arn_suffix, 예: app/<name>/<id>). null이면 알람을 만들지 않는다 — ALB Ingress가 없는 환경(local 등)을 위한 옵션"
  type        = string
  default     = null
}

variable "alb_5xx_threshold_count" {
  description = "5분간 타깃 5xx 응답 수가 이 값을 넘으면 알람"
  type        = number
  default     = 10
}

variable "alb_target_response_time_threshold_seconds" {
  type    = number
  default = 2
}

variable "valkey_cache_cluster_id" {
  description = "Valkey CPU/메모리/eviction 알람이 감시할 대상(CacheClusterId). null이면 알람을 만들지 않는다"
  type        = string
  default     = null
}

variable "valkey_cpu_threshold_percent" {
  description = "EngineCPUUtilization 임계값 (CPUUtilization 대신 이 메트릭을 쓰는 이유는 valkey_alarms.tf 참고)"
  type        = number
  default     = 80
}

variable "valkey_memory_threshold_percent" {
  type    = number
  default = 80
}

variable "valkey_evictions_threshold_count" {
  description = "5분간 eviction 발생 건수가 이 값을 넘으면 알람 (기본 0 — 정상적으로는 발생하면 안 되는 상황)"
  type        = number
  default     = 0
}

variable "tags" {
  description = "모든 리소스에 붙일 공통 태그"
  type        = map(string)
  default     = {}
}

variable "aws_region" {
  description = "대시보드 위젯의 region 필드에 쓰는 값. 이 모듈은 provider 설정을 갖지 않아 별도로 받는다"
  type        = string
  default     = "ap-northeast-2"
}

variable "application_log_group_name" {
  description = "Fluent Bit가 쓰는 앱 로그 그룹 이름(modules/eks의 application_log_group_name output) — 대시보드에 수집량(IncomingBytes) 위젯을 추가할 대상. null이면 위젯을 만들지 않는다(Fluent Bit 미설치 환경용)"
  type        = string
  default     = null
}
