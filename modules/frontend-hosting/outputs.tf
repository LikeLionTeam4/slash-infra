output "bucket_name" {
  description = "빌드 산출물을 업로드할 S3 버킷 이름 (CI의 `aws s3 sync` 대상)"
  value       = aws_s3_bucket.site.id
}

output "bucket_arn" {
  description = "CI 배포 Role의 IAM 정책이 참조할 버킷 ARN"
  value       = aws_s3_bucket.site.arn
}

output "cloudfront_distribution_arn" {
  description = "CI 배포 Role의 IAM 정책이 참조할 CloudFront 배포 ARN"
  value       = aws_cloudfront_distribution.site.arn
}

output "cloudfront_distribution_id" {
  description = "배포 후 캐시 무효화(invalidation)에 쓸 CloudFront 배포 ID"
  value       = aws_cloudfront_distribution.site.id
}

output "cloudfront_domain_name" {
  description = "CloudFront가 발급한 기본 도메인 (*.cloudfront.net)"
  value       = aws_cloudfront_distribution.site.domain_name
}

output "site_url" {
  description = "커스텀 도메인으로 접속하는 최종 URL"
  value       = "https://${var.domain_name}"
}
