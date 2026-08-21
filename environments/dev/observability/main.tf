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
    bucket = "slash-tfstate-061039804626"
    key    = "dev/database.tfstate"
    region = "ap-northeast-2"
  }
}

data "terraform_remote_state" "eks" {
  backend = "s3"

  config = {
    bucket = "slash-tfstate-061039804626"
    key    = "dev/eks.tfstate"
    region = "ap-northeast-2"
  }
}

data "terraform_remote_state" "cognito" {
  backend = "s3"

  config = {
    bucket = "slash-tfstate-061039804626"
    key    = "dev/cognito.tfstate"
    region = "ap-northeast-2"
  }
}

# AWS Load Balancer Controller가 만든 ALB는 Terraform이 직접 관리하지 않는다(K8s Ingress가
# 만듦, modules/eks/alb_controller.tf 참고). group.name을 안 써서(helm/slash-api/templates/ingress.yaml)
# Ingress 1개당 전용 ALB가 뜨고 이름이 자동 생성돼 재생성될 때마다 바뀔 수 있어서, 이름 대신
# 컨트롤러가 항상 붙이는 태그로 조회한다(2026-08-19 실제 ALB에서 확인한 태그 그대로).
# 주의: Ingress를 잠깐이라도 내려서 ALB가 사라진 상태로 apply하면 이 data source가 실패한다.
data "aws_lb" "slash_api" {
  tags = {
    "elbv2.k8s.aws/cluster" = data.terraform_remote_state.eks.outputs.cluster_name
    "ingress.k8s.aws/stack" = "default/slash-api"
  }
}

module "observability" {
  source = "../../../modules/observability"

  name_prefix = "slash"
  environment = "dev"

  rds_instance_id = data.terraform_remote_state.database.outputs.rds_instance_id

  # 단일 노드 replication group이라 실제 CacheClusterId는 -001 접미사가 붙는다
  # (2026-08-19 aws elasticache describe-cache-clusters로 확인).
  valkey_cache_cluster_id = "${data.terraform_remote_state.database.outputs.valkey_replication_group_id}-001"

  alb_arn_suffix = data.aws_lb.slash_api.arn_suffix

  eks_cluster_name            = data.terraform_remote_state.eks.outputs.cluster_name
  cognito_user_pool_id        = data.terraform_remote_state.cognito.outputs.user_pool_id
  valkey_replication_group_id = data.terraform_remote_state.database.outputs.valkey_replication_group_id

  # NAT Gateway 삭제 사고(2026-08-21, slash-infra#56) 계기로 팀원 알림 추가.
  alarm_emails = [
    "ryjun91@naver.com",
    "ryjun91@gmail.com",
    "baegugureview@gmail.com",
  ]
}
