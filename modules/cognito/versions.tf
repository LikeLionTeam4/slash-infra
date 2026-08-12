terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    # aws_cognito_managed_login_branding가 hashicorp/aws v5.100(현재 최신 5.x)까지도 아직 없다
    # (terraform providers schema로 직접 확인함) — Cloud Control 기반 awscc는 CloudFormation
    # 리소스 타입이 나오는 대로 따라가서 이미 지원한다.
    awscc = {
      source  = "hashicorp/awscc"
      version = "~> 1.96"
    }
  }
}
