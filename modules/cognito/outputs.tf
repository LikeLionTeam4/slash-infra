output "user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "user_pool_client_id" {
  description = "slash-web이 브라우저에서 직접 쓰는 퍼블릭 클라이언트 ID (시크릿 없음)"
  value       = aws_cognito_user_pool_client.web.id
}

output "issuer_url" {
  description = "slash-api가 JWT 서명을 검증할 때 쓰는 issuer/JWKS 기준 URL (https://cognito-idp.<region>.amazonaws.com/<user_pool_id>)"
  value       = "https://${aws_cognito_user_pool.main.endpoint}"
}

output "hosted_domain" {
  description = "Google 로그인(OAuth 리다이렉트)에 쓰는 Cognito 도메인. 이메일 OTP만 쓸 때는 불필요"
  value       = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${data.aws_region.current.name}.amazoncognito.com"
}
