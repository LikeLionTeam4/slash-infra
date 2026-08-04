variable "name_prefix" {
  description = "리소스명 접두사"
  type        = string
  default     = "slash"
}

variable "environment" {
  description = "환경 이름 (dev / prod 등) — 리소스명과 Environment 태그에 사용"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR 블록"
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "사용할 가용영역 목록. public/private_app/private_db subnet cidr 목록과 순서·길이가 같아야 한다."
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2c"]
}

variable "public_subnet_cidrs" {
  description = "AZ 순서에 대응하는 public 서브넷 CIDR 목록 (ALB, NAT Gateway)"
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "private_app_subnet_cidrs" {
  description = "AZ 순서에 대응하는 private-app 서브넷 CIDR 목록 (EKS 노드)"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "private_db_subnet_cidrs" {
  description = "AZ 순서에 대응하는 private-db 서브넷 CIDR 목록 (RDS, Valkey) — 인터넷 기본 경로 없음"
  type        = list(string)
  default     = ["10.0.20.0/24", "10.0.21.0/24"]
}

variable "nat_gateway_per_az" {
  description = "true면 AZ당 NAT Gateway 1개(가용성형), false면 1개만 만들어 모든 private-app 서브넷이 공유(비용형)"
  type        = bool
  default     = true
}

variable "flow_log_retention_days" {
  description = "VPC Flow Log를 저장하는 S3 버킷의 오브젝트 만료(수명주기) 일수"
  type        = number
  default     = 30
}

variable "tags" {
  description = "모든 리소스에 붙일 공통 태그"
  type        = map(string)
  default     = {}
}
