terraform {
  required_version = ">= 1.10.0"

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

  backend "s3" {
    bucket       = "slash-tfstate-727646470302"
    key          = "dev/eks.tfstate"
    region       = "ap-northeast-2"
    use_lockfile = true
  }
}

provider "aws" {
  region = "ap-northeast-2"

  default_tags {
    tags = {
      Project     = "slash"
      Service     = "eks"
      Environment = "dev"
      ManagedBy   = "terraform"
      CostCenter  = "slash"
    }
  }
}

data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket = "slash-tfstate-727646470302"
    key    = "dev/network.tfstate"
    region = "ap-northeast-2"
  }
}

module "eks" {
  source = "../../../modules/eks"

  name_prefix = "slash"
  environment = "dev"

  vpc_id                 = data.terraform_remote_state.network.outputs.vpc_id
  private_app_subnet_ids = values(data.terraform_remote_state.network.outputs.private_app_subnet_ids)
  eks_security_group_id  = data.terraform_remote_state.network.outputs.eks_security_group_id

  # ECR은 이제 modules/eks에 없다(2026-08-12, environments/bootstrap의 modules/ecr로 이전
  # — docs §6). local/eks 마이그레이션 때와 동일하게, dev/eks도 ECR을 만들지 않는다 —
  # 그래서 local과 이름 충돌 없이 그대로 apply된다.
}
