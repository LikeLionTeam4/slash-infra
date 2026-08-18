variable "name_prefix" {
  description = "리소스명 접두사"
  type        = string
  default     = "slash"
}

variable "environment" {
  description = "환경 이름 (dev / prod 등) — 리소스명과 Environment 태그에 사용"
  type        = string
}

variable "subnet_id" {
  description = "EC2를 배치할 private-app 서브넷 ID (network 모듈의 private_app_subnet_ids 중 하나)"
  type        = string
}

variable "security_group_id" {
  description = "network 모듈이 만든 ollama 보안그룹 ID (EKS SG에서만 11434 인바운드 허용)"
  type        = string
}

variable "instance_type" {
  description = "Ollama를 돌릴 GPU 인스턴스 타입"
  type        = string
  default     = "g4dn.xlarge"
}

variable "ollama_model" {
  description = "user_data가 최초 부팅 시 pull할 Ollama 모델"
  type        = string
  default     = "gemma3:4b"
}

variable "root_volume_size" {
  description = "루트 EBS 볼륨 크기(GB) — 베이스 AMI 스냅샷이 이미 75GB라 이보다 작게는 못 줄인다"
  type        = number
  default     = 75
}

variable "tags" {
  description = "모든 리소스에 붙일 공통 태그"
  type        = map(string)
  default     = {}
}

variable "use_spot" {
  description = "true면 Spot으로 띄운다(2026-08-18 비용 재검토, On-demand 대비 60~90% 절감). AWS가 용량을 회수하면 정지(터미네이트 아님)"
  type        = bool
  default     = true
}

variable "schedule_enabled" {
  description = "true면 EventBridge Scheduler로 인스턴스를 지정 시간에만 켜둔다"
  type        = bool
  default     = true
}

variable "schedule_start_cron" {
  description = "인스턴스를 켜는 스케줄(schedule_timezone 기준). aws_scheduler_schedule cron 표현식"
  type        = string
  default     = "cron(0 9 ? * MON-FRI *)"
}

variable "schedule_stop_cron" {
  description = "인스턴스를 끄는 스케줄(schedule_timezone 기준). aws_scheduler_schedule cron 표현식"
  type        = string
  default     = "cron(0 21 ? * MON-FRI *)"
}

variable "schedule_timezone" {
  description = "스케줄 cron을 해석할 타임존"
  type        = string
  default     = "Asia/Seoul"
}
