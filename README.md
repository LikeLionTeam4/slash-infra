# infra

Slash AWS 인프라. 역할별 재사용 모듈(`modules/`)과 이를 조합하는 환경(`environments/`)으로 나눈다.

```
modules/
  frontend-hosting/  # S3 + CloudFront + ACM + Route53 — 정적 프론트엔드 호스팅
  network/           # VPC + 3-tier 서브넷 + SG(EKS/DB) + S3 Gateway Endpoint + VPC Flow Log
environments/
  bootstrap/          # 모든 환경이 공유하는 state용 S3 버킷 (최초 1회만 apply)
  dev/
    frontend/         # frontend-hosting 모듈을 dev 값으로 조합
    network/          # network 모듈을 dev 값으로 조합
```

환경 디렉터리마다 별도 state를 가지므로, 전체를 한 번에 적용할 수도 있고(`terraform apply`)
바뀐 모듈만 골라 적용할 수도 있다(`-target` 또는 필요한 환경 디렉터리에서만 apply).

## 사용법 (예: environments/dev/frontend)

```
cd environments/dev/frontend
cp terraform.tfvars.example terraform.tfvars   # 실제 값으로 채우기
terraform init
terraform plan
```

`environments/dev/network`는 변수 없이 바로 쓸 수 있다 (기본값이 이미 dev 값):

```
cd environments/dev/network
terraform init
terraform plan   # 유효한 AWS 자격증명 필요 (aws sts get-caller-identity로 먼저 확인)
```

자격증명 없이도 `terraform validate`까지는 로컬에서 확인 가능하다 — `plan`부터는 AWS API 호출이 필요하다.

## 다음 단계 (아직 미구현)

`docs/aws-architecture.md`에 설계는 정리되어 있지만 아직 모듈이 없는 부분:

- RDS PostgreSQL(§7-1) + Valkey/ElastiCache(§7-2) — `network` 모듈이 만든 `private_db_subnet_ids`, `db_security_group_id`를 그대로 사용
- EKS 컨트롤플레인 + 초기 EC2 3대(§5) — `network` 모듈의 `private_app_subnet_ids`, `eks_security_group_id` 사용
- API용 ALB Ingress + ACM(§8)

## State 백엔드 부트스트랩 (최초 1회)

다른 모든 환경이 remote state로 쓸 S3 버킷을 만든다. 이 버킷이 없는 상태에서는 각 환경이
local backend로 동작한다.

```
cd environments/bootstrap
terraform init
terraform apply
```

`apply` 후 출력되는 `bucket_name`을 다른 환경의 `backend "s3"` 블록에 아래처럼 연결한다
(DynamoDB 없이 S3 자체 락 기능만 사용, Terraform 1.10+ 필요):

```hcl
terraform {
  backend "s3" {
    bucket       = "<bootstrap이 출력한 bucket_name>"
    key          = "<env>/<service>/terraform.tfstate"
    region       = "ap-northeast-2"
    encrypt      = true
    use_lockfile = true
  }
}
```

자세한 배경은 [docs/aws-architecture.md](docs/aws-architecture.md) §3 참고.

## 아키텍처

전체 AWS 인프라 설계(네트워크, EKS, RDS, CI/CD 등)는 [docs/aws-architecture.md](docs/aws-architecture.md) 참고.

## 관련 저장소

| 저장소 | 역할 |
|---|---|
| [slash-web](https://github.com/LikeLionTeam4/slash-web) | 웹 클라이언트 — React·Vite UI, S3/CloudFront 배포 |
| [slash-api](https://github.com/LikeLionTeam4/slash-api) | 코어 API — 인증, 작업 관리, 실행 위치 결정, DB 연동 |
| [slash-nlu](https://github.com/LikeLionTeam4/slash-nlu) | 자연어 분석 — slash 명령 파싱, 규칙·Kiwi 의도 분류, 인자 추출 |
| [slash-llm](https://github.com/LikeLionTeam4/slash-llm) | LLM 서비스 — Gemma 추론, 요약·대화 생성 |
| [slash-agent](https://github.com/LikeLionTeam4/slash-agent) | 로컬 에이전트 — PC 파일 검색, 상태 조회, 로컬 AI 실행·결과 전달 |
| **slash-infra** (현재) | 인프라 — Terraform(AWS), Helm·ArgoCD 배포 |
| [slash-docs](https://github.com/LikeLionTeam4/slash-docs) | 프로젝트 문서 — 아키텍처, API 계약, ERD, 회의록 |
