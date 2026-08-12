output "bucket_name" {
  description = "Terraform state를 저장하는 S3 버킷 이름 — 다른 환경의 backend \"s3\" 블록에서 이 값을 bucket으로 참조한다."
  value       = aws_s3_bucket.tfstate.id
}

output "bucket_arn" {
  value = aws_s3_bucket.tfstate.arn
}

output "route53_zone_id" {
  description = "sbsh.cloud 존 ID — 각 환경의 frontend/network 모듈 hosted_zone_id 변수로 넘긴다."
  value       = aws_route53_zone.root.zone_id
}

output "route53_name_servers" {
  description = "가비아 등 등록기관에 네임서버로 등록할 NS 레코드 4개."
  value       = aws_route53_zone.root.name_servers
}

output "cloudtrail_bucket_name" {
  value = aws_s3_bucket.cloudtrail.id
}

output "cloudtrail_arn" {
  value = aws_cloudtrail.main.arn
}

output "ecr_repository_urls" {
  description = "local/dev/prod가 공용으로 참조하는 ECR 리포지토리 URL (2026-08-12, modules/eks에서 이전)"
  value       = module.ecr.repository_urls
}
