terraform {
  required_version = ">= 1.5.0"

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
      Service     = "database"
      Environment = "local"
      ManagedBy   = "terraform"
      CostCenter  = "slash"
    }
  }
}

module "database" {
  source = "../../../modules/database"

  name_prefix = "slash"
  environment = "local"

  private_db_subnet_ids = var.private_db_subnet_ids
  db_security_group_id  = var.db_security_group_id

  # local은 개인 실험용이라 NAT(§4)/force_destroy(frontend)와 같은 이유로 비용·편의를 우선한다.
  # dev/prod는 모듈 기본값(Multi-AZ 활성, deletion_protection 활성) 그대로 쓴다.
  rds_multi_az            = false
  rds_deletion_protection = false
  rds_skip_final_snapshot = true
}
