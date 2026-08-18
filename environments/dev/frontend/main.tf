terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket       = "slash-tfstate-061039804626"
    key          = "dev/frontend.tfstate"
    region       = "ap-northeast-2"
    use_lockfile = true
  }
}

provider "aws" {
  region = "ap-northeast-2"

  default_tags {
    tags = {
      Project     = "slash"
      Service     = "frontend"
      Environment = "dev"
      ManagedBy   = "terraform"
      CostCenter  = "slash"
    }
  }
}

# CloudFront ACM 인증서는 반드시 us-east-1 리전이어야 한다 (AWS 제약, local/frontend와 동일).
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}

module "frontend_hosting" {
  source = "../../../modules/frontend-hosting"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  bucket_name    = "${var.bucket_name}-${data.aws_caller_identity.current.account_id}"
  domain_name    = var.domain_name
  hosted_zone_id = var.hosted_zone_id

  # dev는 local과 달리 재생산 가능한 실험 산출물이 아니라 팀이 QA에 쓰는 환경이라
  # force_destroy는 모듈 기본값(false)을 그대로 둔다 — 실수로 지우는 걸 막는다.

  tags = {
    Project     = "slash"
    Service     = "frontend"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

module "frontend_cicd" {
  source = "../../../modules/frontend-cicd"

  name_prefix = "slash"
  environment = "dev"

  bucket_arn                  = module.frontend_hosting.bucket_arn
  cloudfront_distribution_arn = module.frontend_hosting.cloudfront_distribution_arn

  github_repo = "LikeLionTeam4/slash-web"
  # local/frontend와 같은 이유(TODO) — slash-web의 main이 아직 빈 스텁 브랜치라
  # dev를 타겟팅. dev->main 첫 정식 릴리스 시 되돌릴 것.
  github_branch = "dev"

  tags = {
    Project     = "slash"
    Service     = "frontend-cicd"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}
