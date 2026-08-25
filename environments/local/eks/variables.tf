variable "vpc_id" {
  description = "environments/local/network output의 vpc_id"
  type        = string
}

variable "private_app_subnet_ids" {
  description = "environments/local/network output의 private_app_subnet_ids 값들 (list로 넣는다)"
  type        = list(string)
}

variable "eks_security_group_id" {
  description = "environments/local/network output의 eks_security_group_id"
  type        = string
}

variable "team_member_arns" {
  description = "이슈 #63 access entry 검증용 — 테스트 대상 IAM ARN 목록"
  type        = list(string)
  default     = []
}
