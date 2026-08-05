variable "name_prefix" {
  description = "리소스명 접두사"
  type        = string
  default     = "slash"
}

variable "environment" {
  description = "환경 이름 (local / dev / prod 등) — 리소스명과 Environment 태그에 사용"
  type        = string
}

variable "allowed_first_auth_factors" {
  description = "Managed Login 페이지에서 허용할 1차 인증 수단. Cognito API가 PASSWORD 포함을 무조건 요구해서 EMAIL_OTP 단독으로는 못 만든다 — 실제로 Managed Login은 이메일+비밀번호 폼을 기본으로 보여준다(Google 소셜 로그인은 채택하지 않기로 결정, 2026-08-05)"
  type        = list(string)
  default     = ["PASSWORD", "EMAIL_OTP"]
}

variable "callback_urls" {
  description = "Managed Login 로그인 성공 후 돌아올 slash-web URL 목록 (Authorization Code+PKCE 콜백 라우트). 최소 1개 필요 — OAuth 플로우가 항상 켜져 있다"
  type        = list(string)
}

variable "logout_urls" {
  description = "로그아웃 후 돌아올 slash-web URL 목록. 최소 1개 필요"
  type        = list(string)
}

variable "tags" {
  description = "모든 리소스에 붙일 공통 태그"
  type        = map(string)
  default     = {}
}
