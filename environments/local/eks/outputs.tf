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
