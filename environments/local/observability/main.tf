terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
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
      Service     = "observability"
      Environment = "local"
      ManagedBy   = "terraform"
      CostCenter  = "slash"
    }
  }
}

module "observability" {
  source = "../../../modules/observability"

  name_prefix = "slash"
  environment = "local"

  rds_instance_id = var.rds_instance_id
  alarm_emails    = var.alarm_email == null ? [] : [var.alarm_email]
}
