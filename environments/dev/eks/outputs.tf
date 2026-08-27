output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}

output "oidc_provider_url" {
  value = module.eks.oidc_provider_url
}

output "node_role_arn" {
  value = module.eks.node_role_arn
}

output "node_instance_profile_name" {
  value = module.eks.node_instance_profile_name
}

output "karpenter_controller_role_arn" {
  value = module.eks.karpenter_controller_role_arn
}

output "alb_controller_role_arn" {
  value = module.eks.alb_controller_role_arn
}

output "api_certificate_arn" {
  value = aws_acm_certificate.api.arn
}

output "slash_api_role_arn" {
  description = "helm/slash-api/values-dev.yaml의 serviceAccount.roleArn에 채울 값"
  value       = module.eks.slash_api_role_arn
}

output "fluent_bit_role_arn" {
  description = "Fluent Bit Helm 설치 시 ServiceAccount 애노테이션에 넣을 Role ARN"
  value       = module.eks.fluent_bit_role_arn
}

output "application_log_group_name" {
  value = module.eks.application_log_group_name
}
