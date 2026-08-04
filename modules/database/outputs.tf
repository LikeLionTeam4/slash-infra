output "rds_endpoint" {
  value = aws_db_instance.main.endpoint
}

output "rds_master_user_secret_arn" {
  description = "RDS가 자동 생성한 마스터 비밀번호 Secrets Manager ARN — slash-api가 IRSA로 읽어야 함"
  value       = aws_db_instance.main.master_user_secret[0].secret_arn
}

output "rds_db_name" {
  description = "인스턴스 생성 시 자동으로 만들어진 첫 번째 DB 이름. 두 번째 DB는 별도로 만들어야 한다 (모듈 설명 참고)"
  value       = aws_db_instance.main.db_name
}

output "valkey_endpoint" {
  value = aws_elasticache_replication_group.main.primary_endpoint_address
}

output "valkey_secret_arn" {
  description = "Valkey 엔드포인트+AUTH 토큰이 담긴 Secrets Manager ARN"
  value       = aws_secretsmanager_secret.valkey.arn
}
