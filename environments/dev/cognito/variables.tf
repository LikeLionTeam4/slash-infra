variable "callback_urls" {
  description = "Managed Login 로그인 성공 후 돌아올 slash-web의 콜백 라우트. dev.sbsh.cloud는 이슈 #17 결정에 따라 프론트 dev 착수 전까지는 실제로 안 뜨지만, 미리 등록해둬도 무해하고(Cognito가 URL의 실제 가용성을 검증하지 않음) 나중에 dev/frontend 착수 시 재apply할 필요가 없어진다"
  type        = list(string)
  default     = ["http://localhost:5173/callback", "https://dev.sbsh.cloud/callback"]
}

variable "logout_urls" {
  description = "로그아웃 후 돌아올 slash-web URL 목록"
  type        = list(string)
  default     = ["http://localhost:5173", "https://dev.sbsh.cloud"]
}
