terraform {
  # S3 backend의 use_lockfile(DynamoDB 없는 native state locking)을 쓰려면 1.10 이상
  # 필요 — dev부터는 팀 전체가 공유하는 첫 환경이라 backend "local" 대신 처음부터
  # S3로 시작한다(docs/aws-architecture.md §3, environments/bootstrap 참고).
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket       = "slash-tfstate-727646470302"
    key          = "dev/network.tfstate"
    region       = "ap-northeast-2"
    use_lockfile = true
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

  # local과 CIDR이 겹쳐도 서로 peering하지 않는 별개 VPC라 기술적으로는 문제 없지만,
  # 나중에 헷갈리지 않도록 dev는 10.1.0.0/16 대역을 쓴다(local은 10.0.0.0/16 기본값).
  vpc_cidr                 = "10.1.0.0/16"
  public_subnet_cidrs      = ["10.1.0.0/24", "10.1.1.0/24"]
  private_app_subnet_cidrs = ["10.1.10.0/24", "10.1.11.0/24"]
  private_db_subnet_cidrs  = ["10.1.20.0/24", "10.1.21.0/24"]

  # nat_gateway_per_az는 오버라이드하지 않는다 — 모듈 기본값(true, AZ당 1개)이
  # dev/prod가 쓰기로 한 값과 이미 같다(docs §4, local만 false로 깎아둠).
}
