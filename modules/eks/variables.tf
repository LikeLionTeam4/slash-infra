variable "name_prefix" {
  description = "리소스명 접두사"
  type        = string
  default     = "slash"
}

variable "environment" {
  description = "환경 이름 (local / dev / prod 등) — 리소스명과 Environment 태그에 사용"
  type        = string
}

variable "vpc_id" {
  description = "network 모듈이 만든 VPC ID"
  type        = string
}

variable "private_app_subnet_ids" {
  description = "network 모듈의 private_app_subnet_ids — EKS 클러스터/노드그룹을 배치할 서브넷"
  type        = list(string)
}

variable "eks_security_group_id" {
  description = "network 모듈이 만든 EKS baseline 보안그룹 ID — 노드 launch template에 붙인다"
  type        = string
}

variable "node_instance_type" {
  description = "범용 노드그룹 EC2 인스턴스 타입"
  type        = string
  default     = "t3.medium"
}

variable "node_desired_size" {
  description = "범용 노드그룹 희망 노드 수"
  type        = number
  default     = 3
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 4
}

variable "tags" {
  description = "모든 리소스에 붙일 공통 태그"
  type        = map(string)
  default     = {}
}

variable "slash_api_secret_arns" {
  description = "slash-api IRSA Role에게 읽기 권한을 줄 Secrets Manager ARN 목록(RDS/Valkey). 빈 리스트면 Role 자체를 안 만든다 — local처럼 DB가 없는 환경용"
  type        = list(string)
  default     = []
}
