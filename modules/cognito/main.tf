# 사용자 데이터(닉네임, 설정, 히스토리 등)는 이 모듈이 아니라 RDS(slash-api)가 갖는다.
# Cognito는 "로그인 검증 + JWT 발급"까지만 담당 — User Pool은 인증 상태(이메일, 비밀번호/OTP
# 검증 여부)만 들고, sub(불변 UUID)를 slash-api가 자체 users 테이블의 외래키로 쓴다.
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_cognito_user_pool" "main" {
  name = "${var.name_prefix}-users-${var.environment}"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  # USER_AUTH 플로우에서 허용할 1차 인증 수단. 기본값(EMAIL_OTP)은 비밀번호 없이
  # 이메일로 받은 코드만으로 로그인 — Managed Login 페이지가 이 옵션을 보여준다.
  sign_in_policy {
    allowed_first_auth_factors = var.allowed_first_auth_factors
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  tags = var.tags
}

# slash-web은 백엔드 계약(frontend-api-contract.md §5)에 따라 Authorization Code + PKCE로
# Managed Login에 리다이렉트한다 — 그래서 도메인이 항상 필요하다. 커스텀 도메인(ACM+Route53)
# 까지는 아직 안 붙이고, 계정마다 전역 유일해야 하는 Cognito 접두사 도메인을 계정ID로 구분해서
# 무료로 쓴다 — local/frontend의 "버킷명에 계정ID 접미사" 패턴과 동일한 이유.
resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.name_prefix}-${var.environment}-${data.aws_caller_identity.current.account_id}"
  user_pool_id = aws_cognito_user_pool.main.id

  # 명시하지 않으면 예전 Hosted UI(classic, v1)로 생성된다 — 브랜딩 에디터(managed-login-branding
  # API)는 v2에만 적용되므로, 커스텀 브랜딩을 쓰려면 반드시 2로 지정해야 한다.
  managed_login_version = 2
}

# slash-web(정적 SPA, 백엔드 서버 없음)이 브라우저에서 직접 호출하는 퍼블릭 클라이언트라
# 시크릿을 발급하지 않는다 — SPA는 시크릿을 안전하게 보관할 방법이 없어서, 시크릿이 있으면
# 오히려 소스에 노출되기 쉽다.
resource "aws_cognito_user_pool_client" "web" {
  name         = "${var.name_prefix}-web-${var.environment}"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret = false

  explicit_auth_flows = [
    "ALLOW_USER_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]

  supported_identity_providers = ["COGNITO"]

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"] # Implicit은 안 쓴다 — 계약서 §5
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  callback_urls                        = var.callback_urls
  logout_urls                          = var.logout_urls

  # 존재하지 않는 이메일로 로그인 시도해도 "그런 계정 없음"을 노출하지 않고 동일한
  # 에러를 준다 — 계정 존재 여부로 사용자 목록을 추측하는 공격을 막는다.
  prevent_user_existence_errors = "ENABLED"

  # 계약서(frontend-api-contract.md §5) 권장값: Access Token 60분, Refresh Token 7일.
  access_token_validity  = 1
  id_token_validity      = 1
  refresh_token_validity = 7
  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }
}

# Managed Login 화면(로그인 폼) 브랜딩 — DESIGN.md 다크 테마 토큰(서페이스 #12141f,
# 전경색 #f2f4f8 등)과 실제 로고(logo.png, public/logo.png와 동일)를 반영한다.
#
# 이 리소스는 이번에 처음 Terraform으로 들여온 게 아니라, 이미 AWS 콘솔/API로
# 직접 만들어져 있던 걸 옮겨온 것이다(2026-08-12 발견 — slash-web 쪽에서 로그인 화면을
# 확인하다가 존재를 알게 됐다). 그 전까지는 코드 어디에도 없는 순수 드리프트였다 —
# 이 모듈을 재적용하거나 도메인 리소스를 다시 만들면 그대로 사라질 수 있는 상태였다.
resource "awscc_cognito_managed_login_branding" "web" {
  user_pool_id = aws_cognito_user_pool.main.id
  # client_id는 실제로 필수다 — 처음엔 옛 계정에서 import한 기존 리소스에 뒤늦게 넣으면
  # CloudFormation의 Read 핸들러가 이 값을 안 돌려줘서 Terraform이 "생성 시점에만 되는 값이
  # 바뀌었다"고 보고 destroy+create로 갈아엎으려 해서 일부러 뺐었는데(2026-08-12), 그건 그
  # 특정 import 상황에서만 필요한 우회였다. 계정을 새로 판 뒤 처음부터 다시 만들어보니
  # Cognito API 자체가 생성 시점엔 client_id 없이는 거부한다(`Value null at 'clientId' failed
  # to satisfy constraint`) — 옛 계정 리소스를 전부 지운 지금은 이 우회가 필요 없어서 되돌린다.
  client_id                   = aws_cognito_user_pool_client.web.id
  use_cognito_provided_values = false

  settings = file("${path.module}/branding/settings.json")

  # Cognito의 update-managed-login-branding는 (category, color_mode) 기준으로 upsert만
  # 한다 — assets 배열에서 항목을 빼도 서버에 이미 있는 자산은 지워지지 않는다(직접 raw
  # API로도 같은 결과 확인함, Terraform/Cloud Control 쪽 문제가 아니다). 그래서 DYNAMIC도
  # 계속 선언해서 최소한 내용은 LIGHT/DARK와 같은 작은 이미지로 맞춰 둔다 — 안 그러면 옛날에
  # 콘솔로 올렸던 500x500(263KB) 원본이 영영 그대로 남아 매 plan마다 diff가 뜬다.
  #
  # 순서도 AWS가 실제로 돌려주는 순서(DARK, DYNAMIC, LIGHT)를 그대로 맞춘다 — Cloud Control이
  # 이 리스트를 위치 기준으로 비교해서, 내용이 완전히 같아도 순서가 다르면 매번 diff가 뜬다.
  assets = [
    {
      category   = "FORM_LOGO"
      color_mode = "DARK"
      extension  = "PNG"
      bytes      = filebase64("${path.module}/branding/logo.png")
    },
    {
      category   = "FORM_LOGO"
      color_mode = "DYNAMIC"
      extension  = "PNG"
      bytes      = filebase64("${path.module}/branding/logo.png")
    },
    {
      category   = "FORM_LOGO"
      color_mode = "LIGHT"
      extension  = "PNG"
      bytes      = filebase64("${path.module}/branding/logo.png")
    },
  ]
}
