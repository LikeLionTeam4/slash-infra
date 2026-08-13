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
