output "user_pool_id" {
  value = module.cognito.user_pool_id
}

output "user_pool_client_id" {
  value = module.cognito.user_pool_client_id
}

output "issuer_url" {
  value = module.cognito.issuer_url
}

output "hosted_domain" {
  value = module.cognito.hosted_domain
}
