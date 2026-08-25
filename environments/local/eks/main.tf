terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
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
      Service     = "eks"
      Environment = "local"
      ManagedBy   = "terraform"
      CostCenter  = "slash"
    }
  }
}

module "eks" {
  source = "../../../modules/eks"

  name_prefix = "slash"
  environment = "local"

  vpc_id                 = var.vpc_id
  private_app_subnet_ids = var.private_app_subnet_ids
  eks_security_group_id  = var.eks_security_group_id

  team_member_arns = var.team_member_arns
}
