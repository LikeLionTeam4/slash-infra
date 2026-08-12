terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    # modules/cognito의 Managed Login 브랜딩 리소스(awscc_cognito_managed_login_branding)가
    # 필요로 한다 — versions.tf 주석 참고.
    awscc = {
      source  = "hashicorp/awscc"
      version = "~> 1.96"
    }
  }

  # 테스트 단계라 로컬 state로 시작한다. environments/bootstrap을 apply해서
  # state용 S3 버킷이 생기면 backend "s3"로 옮긴다.
  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "aws" {
  region = "ap-northeast-2"

  default_tags {
    tags = {
      Project     = "slash"
      Service     = "cognito"
      Environment = "local"
      ManagedBy   = "terraform"
      CostCenter  = "slash"
    }
  }
}

provider "awscc" {
  region = "ap-northeast-2"
}

module "cognito" {
  source = "../../../modules/cognito"

  name_prefix = "slash"
  environment = "local"

  callback_urls = var.callback_urls
  logout_urls   = var.logout_urls
}
