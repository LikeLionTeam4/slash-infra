terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    # Valkey AUTH 토큰을 생성하기 위해 필요.
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
