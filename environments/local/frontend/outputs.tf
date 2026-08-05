output "site_url" {
  value = module.frontend_hosting.site_url
}

output "cloudfront_domain_name" {
  value = module.frontend_hosting.cloudfront_domain_name
}

output "cloudfront_distribution_id" {
  value = module.frontend_hosting.cloudfront_distribution_id
}

output "bucket_name" {
  value = module.frontend_hosting.bucket_name
}

output "frontend_deploy_role_arn" {
  value = module.frontend_cicd.role_arn
}
