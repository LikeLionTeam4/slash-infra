terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
      # CloudFront에 붙는 ACM 인증서는 반드시 us-east-1이어야 해서, 루트가 리전이 다른
      # provider alias를 넘겨줄 수 있도록 선언해둔다.
      configuration_aliases = [aws.us_east_1]
    }
  }
}
