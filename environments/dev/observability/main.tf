terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket       = "slash-tfstate-727646470302"
    key          = "dev/observability.tfstate"
    region       = "ap-northeast-2"
    use_lockfile = true
  }
}

provider "aws" {
  region = "ap-northeast-2"

  default_tags {
    tags = {
      Project     = "slash"
      Service     = "observability"
      Environment = "dev"
      ManagedBy   = "terraform"
      CostCenter  = "slash"
    }
  }
}

data "terraform_remote_state" "database" {
  backend = "s3"

  config = {
    bucket = "slash-tfstate-727646470302"
    key    = "dev/database.tfstate"
    region = "ap-northeast-2"
  }
}

module "observability" {
  source = "../../../modules/observability"

  name_prefix = "slash"
  environment = "dev"

  rds_instance_id = data.terraform_remote_state.database.outputs.rds_instance_id
  # alarm_email은 비워둔다 — SNS 토픽만 만들고, 구독은 필요할 때 콘솔/CLI로 추가.
}
