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
    bucket       = "slash-tfstate-061039804626"
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
    bucket = "slash-tfstate-061039804626"
    key    = "dev/network.tfstate"
    region = "ap-northeast-2"
  }
}

# slash-api IRSA Role(secrets_arns)용 — database가 eks보다 먼저 apply돼 있어야 한다
# (기존 순서: network → cognito/database/eks, docs/operations-log.md §5 참고).
data "terraform_remote_state" "database" {
  backend = "s3"

  config = {
    bucket = "slash-tfstate-061039804626"
    key    = "dev/database.tfstate"
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

  slash_api_secret_arns = [
    data.terraform_remote_state.database.outputs.rds_master_user_secret_arn,
    data.terraform_remote_state.database.outputs.valkey_secret_arn,
  ]

  # ECR은 이제 modules/eks에 없다(2026-08-12, environments/bootstrap의 modules/ecr로 이전
  # — docs §6). local/eks 마이그레이션 때와 동일하게, dev/eks도 ECR을 만들지 않는다 —
  # 그래서 local과 이름 충돌 없이 그대로 apply된다.

  # 2026-08-21: 09~21시 가동을 평일(MON-FRI)에서 매일로 확대하기로 결정(operations-log.md
  # §12-3) — 팀원이 주말에도 작업하고 싶다는 요청. 모듈 기본값(MON-FRI)은 "평일만"이 맞는
  # 일반적인 기본값이라 그대로 두고, 이 결정은 dev 환경에서만 명시적으로 오버라이드한다.
  schedule_start_cron = "cron(0 9 ? * * *)"
  schedule_stop_cron  = "cron(0 21 ? * * *)"

  team_member_arns = var.team_member_arns
}
