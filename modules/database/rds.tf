# private-db 서브넷 2개(AZ 2개) 이상을 요구하는 RDS의 DB subnet group.
resource "aws_db_subnet_group" "main" {
  name       = "${var.name_prefix}-db-${var.environment}"
  subnet_ids = var.private_db_subnet_ids
  tags       = var.tags
}

# 마스터 비밀번호는 우리가 만들지 않는다 — manage_master_user_password를 켜면 RDS가
# 알아서 랜덤 생성해서 Secrets Manager에 저장하고, 로테이션까지 관리해준다.
resource "aws_db_instance" "main" {
  identifier = "${var.name_prefix}-rds-${var.environment}"

  engine         = "postgres"
  engine_version = "16"
  instance_class = var.rds_instance_class

  allocated_storage     = var.rds_allocated_storage
  max_allocated_storage = var.rds_max_allocated_storage
  storage_type          = "gp3"

  db_name  = var.rds_db_name
  username = "slash_admin"

  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.db_security_group_id]
  publicly_accessible    = false

  multi_az                = var.rds_multi_az
  backup_retention_period = var.rds_backup_retention_days

  deletion_protection       = var.rds_deletion_protection
  skip_final_snapshot       = var.rds_skip_final_snapshot
  final_snapshot_identifier = var.rds_skip_final_snapshot ? null : "${var.name_prefix}-rds-${var.environment}-final"

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-rds-${var.environment}"
  })
}
