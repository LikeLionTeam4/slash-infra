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
    key          = "dev/llm-runtime.tfstate"
    region       = "ap-northeast-2"
    use_lockfile = true
  }
}

provider "aws" {
  region = "ap-northeast-2"

  default_tags {
    tags = {
      Project     = "slash"
      Service     = "llm-runtime"
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

module "llm_runtime" {
  source = "../../../modules/llm-runtime"

  name_prefix = "slash"
  environment = "dev"

  # private_app_subnet_ids는 AZ => subnet ID 맵이라 첫 AZ 것 하나만 쓴다 —
  # 인스턴스 1대라 다중 AZ 분산이 필요 없다(§5-1).
  subnet_id         = values(data.terraform_remote_state.network.outputs.private_app_subnet_ids)[0]
  security_group_id = data.terraform_remote_state.network.outputs.ollama_security_group_id
}
