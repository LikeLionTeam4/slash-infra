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

  # 이 루트는 다른 모든 환경이 쓸 state 백엔드(S3 버킷)를 직접 만드는 부트스트랩이라
  # 아직 참조할 backend가 없다 — local state로 관리한다. apply 후 .terraform 디렉터리와
  # terraform.tfstate는 안전한 곳에 백업해둘 것 (유실 시 버킷 이름은 계정 ID로 결정되는
  # 값이라 terraform import로 복구 가능).
}

provider "aws" {
  region = "ap-northeast-2"
}
