terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  backend "s3" {
    bucket       = "slash-tfstate-727646470302"
    key          = "dev/database.tfstate"
    region       = "ap-northeast-2"
    use_lockfile = true
  }
}

provider "aws" {
  region = "ap-northeast-2"

  default_tags {
    tags = {
      Project     = "slash"
      Service     = "database"
      Environment = "dev"
      ManagedBy   = "terraform"
      CostCenter  = "slash"
    }
  }
}

# local은 network output을 terraform.tfvars에 수동으로 복사해 넣지만(각자 계정,
# 각자 노트북이라 그게 더 단순함), dev는 팀 전체가 같은 S3 state를 공유하는 첫 환경이라
# terraform_remote_state로 직접 참조한다 — 값을 손으로 옮기다 오탈자/stale value가
# 생길 여지를 없앤다.
data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket = "slash-tfstate-727646470302"
    key    = "dev/network.tfstate"
    region = "ap-northeast-2"
  }
}

module "database" {
  source = "../../../modules/database"

  name_prefix = "slash"
  environment = "dev"

  private_db_subnet_ids = values(data.terraform_remote_state.network.outputs.private_db_subnet_ids)
  db_security_group_id  = data.terraform_remote_state.network.outputs.db_security_group_id

  # rds_multi_az는 오버라이드하지 않는다 — 모듈 기본값(true)이 dev/prod가 쓰기로 한 값과
  # 이미 같다(docs §7-1, local만 false로 깎아둔 것).
  #
  # deletion_protection/skip_final_snapshot은 이번 dev 착수 라운드가 "apply→검증→destroy"
  # 사이클(2026-08-12 결정)이라 local과 동일하게 꺼둔다 — dev가 나중에 상시 운영으로
  # 전환되면(팀 합의 후) 이 오버라이드를 지워서 모듈 기본값(보호 켜짐)으로 되돌려야 한다.
  rds_deletion_protection = false
  rds_skip_final_snapshot = true
}
