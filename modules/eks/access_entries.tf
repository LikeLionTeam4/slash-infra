variable "team_member_arns" {
  description = "EKS Access Entry로 클러스터 admin 권한을 부여할 IAM 사용자/역할 ARN 목록(이슈 #63)"
  type        = list(string)
  default     = []
}

resource "aws_eks_access_entry" "team" {
  for_each      = toset(var.team_member_arns)
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = each.value
  tags          = var.tags
}

resource "aws_eks_access_policy_association" "team_admin" {
  for_each      = aws_eks_access_entry.team
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = each.value.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}
