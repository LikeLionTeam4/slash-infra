terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    # EKS 클러스터의 OIDC 발급자 인증서 thumbprint를 가져오기 위해 필요
    # (aws_iam_openid_connect_provider가 요구).
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}
