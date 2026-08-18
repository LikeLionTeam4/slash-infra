variable "name_prefix" {
  description = "리소스명 접두사"
  type        = string
  default     = "slash"
}

variable "environment" {
  description = "환경 이름 (local / dev / prod 등) — 리소스명과 Environment 태그에 사용"
  type        = string
}

variable "private_db_subnet_ids" {
  description = "network 모듈의 private_db_subnet_ids — RDS/Valkey를 배치할 서브넷 (AZ 2개 이상 필요)"
  type        = list(string)
}

variable "db_security_group_id" {
  description = "network 모듈이 만든 DB 보안그룹 ID (EKS SG에서만 인바운드 허용)"
  type        = string
}

variable "rds_instance_class" {
  description = "RDS 인스턴스 클래스"
  type        = string
  default     = "db.t4g.small"
}

variable "rds_allocated_storage" {
  description = "RDS 초기 스토리지(GB, gp3)"
  type        = number
  default     = 20
}

variable "rds_max_allocated_storage" {
  description = "RDS 스토리지 오토스케일링 상한(GB)"
  type        = number
  default     = 100
}

variable "rds_multi_az" {
  description = "true면 Multi-AZ 활성화 (dev/prod 기본값). local처럼 비용을 아낄 환경은 false로 오버라이드"
  type        = bool
  default     = true
}

variable "rds_backup_retention_days" {
  type    = number
  default = 7
}

variable "rds_db_name" {
  description = "인스턴스 생성 시 자동으로 만들어지는 첫 번째 데이터베이스 이름. 두 번째 DB(slash_demo 등)는 private-db 서브넷 안에서만 접근 가능해 Terraform이 아니라 별도 접속 경로(SSM 터널, EKS Job 등)로 만들어야 한다."
  type        = string
  default     = "slash_dev"
}

variable "rds_deletion_protection" {
  description = "true면 실수로 terraform destroy해도 RDS가 안 지워짐. local은 편의상 false로 오버라이드"
  type        = bool
  default     = true
}

variable "rds_skip_final_snapshot" {
  description = "destroy 시 최종 스냅샷 생략 여부. local은 true로 오버라이드(스냅샷 불필요)"
  type        = bool
  default     = false
}

variable "valkey_node_type" {
  description = "ElastiCache Valkey 노드 타입"
  type        = string
  default     = "cache.t4g.micro"
}

variable "tags" {
  description = "모든 리소스에 붙일 공통 태그"
  type        = map(string)
  default     = {}
}

variable "schedule_enabled" {
  description = "true면 EventBridge Scheduler로 RDS를 지정 시간에만 띄운다(Valkey는 stop/start API가 없어 대상 아님)"
  type        = bool
  default     = true
}

variable "schedule_start_cron" {
  description = "RDS를 시작하는 스케줄(schedule_timezone 기준). aws_scheduler_schedule cron 표현식"
  type        = string
  default     = "cron(0 9 ? * MON-FRI *)"
}

variable "schedule_stop_cron" {
  description = "RDS를 정지하는 스케줄(schedule_timezone 기준). aws_scheduler_schedule cron 표현식"
  type        = string
  default     = "cron(0 21 ? * MON-FRI *)"
}

variable "schedule_timezone" {
  description = "스케줄 cron을 해석할 타임존"
  type        = string
  default     = "Asia/Seoul"
}
