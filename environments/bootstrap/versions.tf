terraform {
  # S3 backend의 use_lockfile(DynamoDB 없는 native state locking)이 1.10에서 도입되고
  # 1.11에서 GA됐다. 이 루트가 만든 버킷을 참조할 다른 환경들이 그 기능을 쓰므로 맞춰둔다.
  required_version = ">=1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~>5.0"
    }
  }

  # 최초 apply 시점엔 이 루트가 다른 모든 환경이 쓸 state 백엔드(S3 버킷)를 직접
  # 만드는 부트스트랩이라 참조할 backend가 없어 local state로 시작했다. 이제 그
  # 버킷이 이미 존재하므로 자기 자신이 만든 버킷을 재사용해 S3로 옮긴다(이슈 #66)
  # — local state가 특정 컴퓨터에만 있어 다른 팀원은 이 환경을 관리할 수 없던 문제.
  backend "s3" {
    bucket       = "slash-tfstate-061039804626"
    key          = "bootstrap.tfstate"
    region       = "ap-northeast-2"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = "ap-northeast-2"
}
