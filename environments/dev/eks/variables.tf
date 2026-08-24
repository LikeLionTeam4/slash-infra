variable "team_member_arns" {
  description = "EKS Access Entry로 클러스터 admin 권한을 부여할 IAM 사용자/역할 ARN 목록(이슈 #63). 이 저장소가 public이라 terraform.tfvars(gitignore 대상)로만 실값을 채운다 — terraform.tfvars.example 참고"
  type        = list(string)
  default     = []
}
