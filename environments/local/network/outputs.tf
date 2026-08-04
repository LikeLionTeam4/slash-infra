output "vpc_id" {
  value = module.network.vpc_id
}

output "public_subnet_ids" {
  value = module.network.public_subnet_ids
}

output "private_app_subnet_ids" {
  value = module.network.private_app_subnet_ids
}

output "private_db_subnet_ids" {
  value = module.network.private_db_subnet_ids
}

output "eks_security_group_id" {
  value = module.network.eks_security_group_id
}

output "db_security_group_id" {
  value = module.network.db_security_group_id
}

output "nat_gateway_ids" {
  value = module.network.nat_gateway_ids
}

output "flow_log_bucket_name" {
  value = module.network.flow_log_bucket_name
}
