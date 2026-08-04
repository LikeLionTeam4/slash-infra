# 계정 전체 API 호출 감사용 트레일 1개 — local/dev/prod가 각자 만들 이유가 없어서
# state 버킷·Route53 zone처럼 "계정당 한 번만" 만드는 bootstrap에 둔다 (§10).
# dev 단계에서는 단일 리전 트레일로 충분하다는 문서 결정을 그대로 따른다.

locals {
  cloudtrail_bucket_name = "slash-cloudtrail-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "cloudtrail" {
  bucket = local.cloudtrail_bucket_name
  tags   = merge(local.tags, { Service = "cloudtrail" })
}

resource "aws_s3_bucket_versioning" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket                  = aws_s3_bucket.cloudtrail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 정확한 보관 기간은 트래픽 실측 후 결정하기로 한 TODO(§13) — 90일을 잠정 기본값으로 둔다.
resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    id     = "expire-old-cloudtrail-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = 90
    }
  }
}

# CloudTrail 서비스가 이 버킷에 로그를 쓸 수 있게 하는 표준 정책 (AWS 문서 그대로).
data "aws_iam_policy_document" "cloudtrail_bucket" {
  statement {
    sid       = "AWSCloudTrailAclCheck"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.cloudtrail.arn]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }

  statement {
    sid       = "AWSCloudTrailWrite"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  policy = data.aws_iam_policy_document.cloudtrail_bucket.json
}

resource "aws_cloudtrail" "main" {
  name           = "slash-trail"
  s3_bucket_name = aws_s3_bucket.cloudtrail.id

  is_multi_region_trail         = false
  include_global_service_events = true
  enable_logging                = true

  tags = merge(local.tags, { Service = "cloudtrail" })

  depends_on = [aws_s3_bucket_policy.cloudtrail]
}
