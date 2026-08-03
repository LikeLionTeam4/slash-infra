output "bucket_name" {
  description = "Terraform state를 저장하는 S3 버킷 이름 — 다른 환경의 backend \"s3\" 블록에서 이 값을 bucket으로 참조한다."
  value       = aws_s3_bucket.tfstate.id
}

output "bucket_arn" {
  value = aws_s3_bucket.tfstate.arn
}
