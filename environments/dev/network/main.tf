terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # 테스트 단계라 로컬 state로 시작한다. environments/bootstrap을 apply해서
  # state용 S3 버킷이 생기면 backend "s3"로 옮긴다 (README §State 백엔드 부트스트랩 참고).
  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "aws" {
  region = "ap-northeast-2"

  default_tags {
    tags = {
      Project     = "slash"
      Service     = "network"
      Environment = "dev"
      ManagedBy   = "terraform"
      CostCenter  = "slash"
    }
  }
}

module "network" {
  source = "../../../modules/network"

  name_prefix = "slash"
  environment = "dev"

  # 공통 태그(Project/Service/Environment/ManagedBy/CostCenter)는 위 provider의
  # default_tags가 모든 리소스에 자동으로 붙여준다 — 여기서는 리소스별 추가 태그가
  # 필요할 때만 tags를 넘긴다 (docs/aws-architecture.md §2).
}
