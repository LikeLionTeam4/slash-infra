data "aws_caller_identity" "current" {}

locals {
  # 버킷명은 전역 유니크해야 하므로 계정 ID를 붙여 충돌을 피한다.
  bucket_name = "slash-tfstate-${data.aws_caller_identity.current.account_id}"

  tags = {
    Project     = "slash"
    Service     = "terraform-state"
    Environment = "shared"
    ManagedBy   = "terraform"
  }
}

resource "aws_s3_bucket" "tfstate" {
  bucket = local.bucket_name
  tags   = local.tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
