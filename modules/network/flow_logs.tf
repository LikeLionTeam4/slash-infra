# VPC Flow Log를 저장하는 전용 S3 버킷. CloudTrail 버킷과 동일하게 버저닝 +
# 수명주기 정책으로 오래된 로그를 자동 정리한다.

data "aws_caller_identity" "current" {}

locals {
  flow_log_bucket_name = "${var.name_prefix}-vpc-flow-logs-${var.environment}-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "flow_logs" {
  bucket = local.flow_log_bucket_name
  tags   = var.tags
}

resource "aws_s3_bucket_versioning" "flow_logs" {
  bucket = aws_s3_bucket.flow_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "flow_logs" {
  bucket = aws_s3_bucket.flow_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "flow_logs" {
  bucket                  = aws_s3_bucket.flow_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "flow_logs" {
  bucket = aws_s3_bucket.flow_logs.id

  rule {
    id     = "expire-old-flow-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = var.flow_log_retention_days
    }
  }
}

resource "aws_flow_log" "vpc" {
  vpc_id               = aws_vpc.main.id
  traffic_type         = "ALL"
  log_destination_type = "s3"
  log_destination      = aws_s3_bucket.flow_logs.arn

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-vpc-flow-log-${var.environment}"
  })
}
