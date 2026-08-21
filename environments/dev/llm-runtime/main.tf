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

  # private_app_subnet_ids는 AZ => subnet ID 맵이라 인스턴스 1대는 AZ 하나만 쓴다.
  # 2026-08-18: Spot 전환 중 ap-northeast-2a에서 g4dn.xlarge
  # Server.InsufficientInstanceCapacity 실제 발생(재시도 5회 전부 실패, CloudTrail로 확인)
  # — AWS 에러 메시지가 권장한 대로 2c로 고정. 굳이 [0]으로 첫 AZ를 쓰지 않고 key로
  # 명시해서 network 모듈의 맵 키 순서가 바뀌어도 안 흔들리게 한다.
  subnet_id         = data.terraform_remote_state.network.outputs.private_app_subnet_ids["ap-northeast-2c"]
  security_group_id = data.terraform_remote_state.network.outputs.ollama_security_group_id

  # 2026-08-18 (같은 날 후속) — 2a에 이어 2c에서도 g4dn.xlarge InsufficientInstanceCapacity
  # 재현(StartInstances 재시도 2회 전부 실패). 하루에 AZ 둘 다에서 용량 회수를 겪어 Spot의
  # 60~90% 절감보다 "업무시간에 못 켜질 수 있다"는 위험이 dev 팀 사용성에 더 크다고 판단 —
  # 09~21시 스케줄(schedule.tf)은 그대로 두고 On-Demand로 전환한다. 월 ~$60~85 -> ~$170.
  use_spot = false

  # 2026-08-21: 09~21시 가동을 평일(MON-FRI)에서 매일로 확대(operations-log.md §12-3 참고,
  # eks/database와 동일한 결정·사유).
  schedule_start_cron = "cron(0 9 ? * * *)"
  schedule_stop_cron  = "cron(0 21 ? * * *)"
}
