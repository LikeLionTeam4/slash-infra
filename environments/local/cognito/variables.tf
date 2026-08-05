variable "callback_urls" {
  description = "Managed Login 로그인 성공 후 돌아올 slash-web의 콜백 라우트(Authorization Code 수신 후 토큰 교환하는 화면). 정확히 일치해야 하므로 경로까지 포함한다"
  type        = list(string)
  default     = ["http://localhost:5173/callback", "https://local.sbsh.cloud/callback"]
}

variable "logout_urls" {
  description = "로그아웃 후 돌아올 slash-web URL 목록 (콜백 처리가 필요 없어서 루트로 충분)"
  type        = list(string)
  default     = ["http://localhost:5173", "https://local.sbsh.cloud"]
}
