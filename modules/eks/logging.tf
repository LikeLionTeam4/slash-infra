# EKS가 enabled_cluster_log_types 활성화 시 로그 그룹을 자동 생성하면 보존기간이
# 무기한("Never expire")으로 잡혀 비용이 계속 쌓인다 — 그걸 막기 위해 EKS보다 먼저
# 이 리소스로 로그 그룹을 직접 만들고 보존기간을 명시한다(이슈 #44).
resource "aws_cloudwatch_log_group" "eks_cluster" {
  name              = "/aws/eks/${var.name_prefix}-eks-${var.environment}/cluster"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

# Fluent Bit(aws-for-fluent-bit)가 slash-api/slash-nlu 파드 stdout/stderr를 여기로 보낸다
# (fluent_bit_irsa.tf 참고) — 같은 이유로 Fluent Bit보다 먼저 Terraform이 그룹을 만들고
# 보존기간을 명시한다. auto_create_group을 켜지 않고 로그 그룹 존재를 전제로 설정할 것
# (helm install 문서: slash-infra/logging/README.md).
resource "aws_cloudwatch_log_group" "application" {
  name              = "/eks/${var.name_prefix}-eks-${var.environment}/application"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}
