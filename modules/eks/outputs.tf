output "cluster_name" {
  value = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.main.endpoint
}

output "cluster_certificate_authority_data" {
  value = aws_eks_cluster.main.certificate_authority[0].data
}

output "oidc_provider_arn" {
  description = "IRSA Role의 신뢰관계에서 참조할 OIDC provider ARN"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_provider_url" {
  value = aws_iam_openid_connect_provider.eks.url
}

output "node_role_arn" {
  description = "범용 노드그룹 및 Karpenter가 띄우는 노드가 공통으로 쓰는 IAM Role"
  value       = aws_iam_role.node.arn
}

output "node_instance_profile_name" {
  description = "Karpenter EC2NodeClass 설정 시 필요"
  value       = aws_iam_instance_profile.node.name
}

output "karpenter_controller_role_arn" {
  description = "Karpenter Helm 설치 시 ServiceAccount 애노테이션에 넣을 Role ARN"
  value       = aws_iam_role.karpenter_controller.arn
}

output "ecr_repository_urls" {
  value = { for name, repo in aws_ecr_repository.services : name => repo.repository_url }
}

output "alb_controller_role_arn" {
  description = "AWS Load Balancer Controller Helm 설치 시 ServiceAccount 애노테이션에 넣을 Role ARN"
  value       = aws_iam_role.alb_controller.arn
}
