resource "aws_elasticache_subnet_group" "main" {
  name       = "${var.name_prefix}-valkey-${var.environment}"
  subnet_ids = var.private_db_subnet_ids
  tags       = var.tags
}

# ElastiCache는 RDS의 manage_master_user_password 같은 자동 관리 기능이 없어서
# AUTH 토큰을 직접 생성해 Secrets Manager에 넣어준다.
resource "random_password" "valkey_auth" {
  length  = 32
  special = false # Valkey/Redis AUTH 토큰은 일부 특수문자를 허용하지 않는다
}

# aws_elasticache_cluster는 auth_token을 지원하지 않아서(replication_group만 지원),
# 단일 노드(replica 없음)라도 replication_group으로 만든다.
resource "aws_elasticache_replication_group" "main" {
  replication_group_id = "${var.name_prefix}-valkey-${var.environment}"
  description          = "${var.name_prefix} valkey (${var.environment})"

  engine             = "valkey"
  node_type          = var.valkey_node_type
  num_cache_clusters = 1
  port               = 6379

  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [var.db_security_group_id]

  automatic_failover_enabled = false # 노드 1개라 failover 대상이 없음

  # AUTH 토큰을 쓰려면 전송 구간 암호화가 필수.
  transit_encryption_enabled = true
  auth_token                 = random_password.valkey_auth.result

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-valkey-${var.environment}"
  })
}

resource "aws_secretsmanager_secret" "valkey" {
  name = "${var.name_prefix}/valkey/${var.environment}"
  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "valkey" {
  secret_id = aws_secretsmanager_secret.valkey.id
  secret_string = jsonencode({
    endpoint   = aws_elasticache_replication_group.main.primary_endpoint_address
    port       = aws_elasticache_replication_group.main.port
    auth_token = random_password.valkey_auth.result
  })
}
