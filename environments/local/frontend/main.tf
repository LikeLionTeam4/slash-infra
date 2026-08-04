terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # 테스트 단계라 로컬 state로 시작한다. 실제로 이 환경을 계속 쓰기로 하면
  # S3 backend(+DynamoDB 잠금)로 옮겨야 한다.
  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "aws" {
  region = "ap-northeast-2"
}

# CloudFront ACM 인증서는 반드시 us-east-1 리전이어야 한다 (AWS 제약).
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

module "frontend_hosting" {
  source = "../../../modules/frontend-hosting"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  bucket_name    = var.bucket_name
  domain_name    = var.domain_name
  hosted_zone_id = var.hosted_zone_id

  tags = {
    Project     = "slash"
    Service     = "frontend"
    Environment = "local"
    ManagedBy   = "terraform"
  }
}
