output "rds_endpoint" {
  value = module.database.rds_endpoint
}

output "rds_master_user_secret_arn" {
  value = module.database.rds_master_user_secret_arn
}

output "rds_db_name" {
  value = module.database.rds_db_name
}

output "valkey_endpoint" {
  value = module.database.valkey_endpoint
}

output "valkey_secret_arn" {
  value = module.database.valkey_secret_arn
}
