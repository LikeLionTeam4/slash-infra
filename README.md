# infra

Slash AWS 인프라. 역할별 재사용 모듈(`modules/`)과 이를 조합하는 환경(`environments/`)으로 나눈다.

```
modules/
  frontend-hosting/  # S3 + CloudFront + ACM + Route53 — 정적 프론트엔드 호스팅
  network/           # VPC + 3-tier 서브넷 + SG(EKS/DB) + S3 Gateway Endpoint + VPC Flow Log
  eks/               # EKS 클러스터 + 범용 노드그룹 + IRSA(OIDC) + Karpenter Role + ALB Controller Role + ECR
  database/          # RDS PostgreSQL + Valkey(ElastiCache) + Secrets Manager
  observability/     # CloudWatch 알람(RDS CPU/스토리지) + SNS 알림
environments/
  bootstrap/          # state용 S3 버킷 + Route53 hosted zone + CloudTrail (계정당 최초 1회만 apply)
  local/              # 개인 맥북에서 배포하는 실험용 환경
    frontend/         # frontend-hosting 모듈을 local 값으로 조합
    network/          # network 모듈을 local 값으로 조합 (NAT 1개로 비용 절감)
    eks/              # eks 모듈을 local 값으로 조합 (ECR만 적용 중 — 클러스터는 검증 후 destroy, 운영 로그 참고)
    database/         # database 모듈을 local 값으로 조합 (아직 미적용, Multi-AZ 비활성으로 비용 절감)
    observability/    # observability 모듈을 local 값으로 조합 (아직 미적용)
  dev/                # prod와 거의 동일한 스펙을 유지하는 공유 테스트 서버 (아직 미구축)
  prod/               # 실제 운영 환경 (아직 미구축)
helm/                 # slash-api/nlu/llm Helm chart (서비스별 디렉터리 + 환경별 values, ArgoCD가 볼 대상)
mock-services/        # 실 서비스 Dockerfile이 없는 동안 ECR/EKS/Helm 파이프라인을 검증하는 placeholder 이미지
```

local/dev/prod는 (같은 사람이 적용한다면) 같은 AWS 계정을 리소스명·태그로만 구분해 쓴다
(부트캠프 공유 계정이라 `slash-` 접두사를 꼭 붙일 것 — 자세한 배경은
[docs/aws-architecture.md](docs/aws-architecture.md) §2, §11 참고). **단, 부트캠프 계정은
사람마다 따로 발급되기 때문에 팀원끼리는 서로 다른 AWS 계정을 쓰게 된다** — 이 문서의
예시 리소스 ID(버킷 이름, zone ID 등)는 특정 계정 하나에서 실습한 결과일 뿐이고, 다른
계정에서 시작하는 방법은 아래 [다른 AWS 계정에서 시작하기](#다른-aws-계정에서-시작하기-팀원용) 참고.

환경 디렉터리마다 별도 state를 가지므로, 전체를 한 번에 적용할 수도 있고(`terraform apply`)
바뀐 모듈만 골라 적용할 수도 있다(`-target` 또는 필요한 환경 디렉터리에서만 apply).

## 사용법 (예: environments/local/frontend)

```
cd environments/local/frontend
cp terraform.tfvars.example terraform.tfvars   # 실제 값으로 채우기 (hosted_zone_id는 bootstrap output)
terraform init
terraform plan
```

`environments/local/network`는 변수 없이 바로 쓸 수 있다 (기본값이 이미 local 값):

```
cd environments/local/network
terraform init
terraform plan   # 유효한 AWS 자격증명 필요 (aws sts get-caller-identity로 먼저 확인)
```

자격증명 없이도 `terraform validate`까지는 로컬에서 확인 가능하다 — `plan`부터는 AWS API 호출이 필요하다.

## 다음 단계 (아직 미구현)

`docs/aws-architecture.md`에 설계는 정리되어 있지만 아직 모듈이 없거나 완전히 안 끝난 부분:

- GPU 노드그룹(`slash-llm`용, §5) — 범용 노드그룹은 `eks` 모듈로 구현 완료, GPU는 인스턴스 타입/개수 미정 ([이슈 #13](https://github.com/LikeLionTeam4/slash-infra/issues/13))
- Karpenter 실제 설치(Helm, NodePool/EC2NodeClass) — IRSA Role은 `eks` 모듈에 준비돼 있지만 아직 한 번도 설치해본 적 없음(컨트롤러 자체는 K8s 내부 리소스라 GitOps로 별도 설치)
- ArgoCD 설치 + `helm/`을 Application으로 등록하는 GitOps 연결 ([이슈 #10](https://github.com/LikeLionTeam4/slash-infra/issues/10)) — `helm/`은 준비됐지만 아직 수동 `helm install`로만 검증
- API용 ALB Ingress에 실제 도메인(`api.dev.sbsh.cloud`) + ACM 연결(§8) — ALB Controller 자체는 IRSA Role apply + Helm 설치 + mock 이미지로 실제 ALB 응답까지 검증 완료(2026-08-11), 도메인 연결은 dev 환경 자체가 미구축이라 아직
- ALB 5xx/GPU 사용률 알람(§10) — 위 둘이 상시로 떠 있게 되면 `observability` 모듈에 추가

`environments/local/{eks,database,observability}`는 코드 작성 + `plan` 검증까지 끝났고, `eks`는
ECR만 상시 적용 중(클러스터/ALB Controller/Helm chart는 apply→검증→destroy 완료, 재현 가능) —
**EKS 컨트롤플레인이 월 ~$75로 지금까지 중 가장 비싸서 상시로 켜두지 않고 그때그때 검증 후
정리하는 방식으로 진행 중**([docs/operations-log.md](docs/operations-log.md) §1 마스터 표 참고).
`helm/README.md`, `mock-services/README.md`에 각각의 사용법이 정리되어 있다.

## State 백엔드 + DNS 부트스트랩 (최초 1회)

다른 모든 환경이 remote state로 쓸 S3 버킷과, local/dev/prod가 공유하는 Route53 hosted
zone(`sbsh.cloud`)을 만든다. 이 버킷이 없는 상태에서는 각 환경이 local backend로 동작한다.

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

`route53_zone_id` 출력값은 `frontend-hosting` 모듈을 쓰는 각 환경의 `hosted_zone_id` 변수로
넘긴다. `route53_name_servers` 출력값(4개)은 가비아 도메인 관리 화면의 네임서버 설정에
그대로 등록해서 `sbsh.cloud`를 Route53으로 위임한다.

자세한 배경은 [docs/aws-architecture.md](docs/aws-architecture.md) §2, §3 참고.

## AWS CLI 프로필

`slash-local` / `slash-dev` / `slash-prod` 세 프로필을 미리 나눠뒀다(`~/.aws/config`).
지금은 셋 다 같은 IAM 사용자 자격증명을 가리키지만, 이름을 분리해뒀기 때문에 나중에 단계별로
다른 계정/사용자를 쓰기로 하면 프로필 값만 바꾸면 된다. 사용 시 `--profile slash-local` 또는
`AWS_PROFILE=slash-local`로 지정.

## dev 클러스터 상태 확인 (Headlamp)

리소스 하나하나 AWS 콘솔에서 찾아보지 않고 EKS 파드 상태를 한눈에 보려면 [Headlamp](https://headlamp.dev) 데스크톱 앱을 쓴다(검토 배경: 이슈 [#47](https://github.com/LikeLionTeam4/slash-infra/issues/47)/[#49](https://github.com/LikeLionTeam4/slash-infra/issues/49)). 클러스터에 아무것도 추가로 설치하지 않는 방식이라 비용은 $0.

### 설치 및 연결

```bash
brew install --cask headlamp
aws eks update-kubeconfig --name slash-eks-dev --region ap-northeast-2 --profile slash-dev
```

앱을 열고 `slash-eks-dev`(계정 `061039804626`)를 선택하면 연결된다. 같은 이름인데 계정이
`727646470302`인 항목이 보이면 무시하거나 `kubectl config delete-context <이름>`으로 지운다 —
부트캠프 계정 재발급([이슈 #21](https://github.com/LikeLionTeam4/slash-infra/issues/21)) 이전
kubeconfig 흔적이다.

### 보는 법

**워크로드 → 디플로이먼트**에서 파드 수(`N/M`)만 확인한다 — N=M이면 정상.

| 서비스 | 정상 값 |
| --- | --- |
| slash-api | 2/2 |
| slash-nlu | 2/2 |
| slash-llm | 1/1 |

숫자가 다르면: 해당 디플로이먼트 클릭 → 파드 목록에서 `Running`이 아닌 파드 클릭 → 로그/Events로
원인 확인. **ReplicaSet 목록은 안 봐도 된다** — 배포할 때마다 쌓이는 이력이라 대부분 `0/0`이 정상이다.

### 참고

- 계정을 팀 전체가 공유하는 구조라(위 §AWS CLI 프로필) 별도 로그인·OIDC·RBAC 설정 없이 바로
  접속된다 — 검토 결과는 이슈 #49 참고.
- 관리형 AWS 서비스(RDS/ALB/Valkey) 상태는 별도 CloudWatch 대시보드에서 확인한다:
  `environments/dev/observability`에서 `terraform output dashboard_url`.

## 다른 AWS 계정에서 시작하기 (팀원용)

부트캠프 계정은 사람마다 따로 발급되므로, 팀원이 이 저장소를 clone해서 apply하면 사실상
**완전히 새 AWS 계정**에서 시작하는 것과 같다. 지금까지 만들어둔 리소스와는 전혀 공유되지
않고(계정이 다르면 state를 나눠 쓸 방법이 없다), 그래도 충돌 없이 잘 되는 부분과 안 되는
부분이 갈린다.

### 사전 준비물

- Terraform 1.10 이상 (`use_lockfile` 기능 때문에 `bootstrap`이 요구), AWS CLI v2
- `local/frontend`까지 테스트하려면 [slash-web](https://github.com/LikeLionTeam4/slash-web) 저장소도 별도 clone (Node/npm)

### 순서

1. **본인 IAM 액세스 키 준비** — 본인 부트캠프 계정에서 발급받은 키로 `aws configure`
   (또는 `aws configure set aws_access_key_id/aws_secret_access_key/region`). 프로필 이름은
   `slash-local`로 맞춰두면 이 문서의 명령어를 그대로 복붙할 수 있다 (`AWS_PROFILE=slash-local`).
2. **`environments/bootstrap` apply** — 본인 계정에 본인만의 state 버킷(`slash-tfstate-<본인 계정ID>`)과
   Route53 zone이 생긴다. 버킷 이름에 계정ID가 붙어서 다른 사람 것과 안 겹친다.
3. **`environments/local/network` apply** — 그대로 문제없이 된다. VPC/서브넷/보안그룹 실습은 이것만으로 충분.
4. **`environments/local/frontend`는 주의가 필요하다**:
   - `bucket_name`은 **전역에서 유일**해야 하는데 `terraform.tfvars.example`의 `slash-web-local`은
     이미 다른 계정에서 선점돼 있을 수 있다 — 본인 계정ID나 이름을 붙여서 겹치지 않게 바꿀 것.
   - **더 중요한 문제**: 이 모듈은 `hosted_zone_id`로 넘긴 Route53 zone이 실제로 인터넷에서
     도달 가능해야 ACM 인증서의 DNS 검증(`aws_acm_certificate_validation`)이 끝난다. 본인 계정에
     새로 만든 `sbsh.cloud` zone은 가비아가 위임한 진짜 zone이 아니라서(가비아는 원본 계정의
     zone 하나만 가리킨다) **영원히 검증되지 않고 apply가 멈춘다.**
   - 그래서 실제로 테스트하려면: (a) 본인이 소유하고 위임 가능한 다른 도메인으로 `domain_name`을
     바꾸거나, (b) 이 모듈은 건너뛰고 `network`까지만 연습하는 것을 권장.
5. **destroy는 [docs/operations-log.md](docs/operations-log.md) §5의 순서**(frontend → network → bootstrap)를
   본인 계정 안에서 그대로 따르면 된다 — 계정이 다르니 다른 사람 리소스에 영향 없음.

## 아키텍처

전체 AWS 인프라 설계(네트워크, EKS, RDS, CI/CD 등)는 [docs/aws-architecture.md](docs/aws-architecture.md) 참고.

**Terraform apply/destroy 순서와 구현된 것/안 된 것 전체 표**는 [docs/operations-log.md §1](docs/operations-log.md#1-전체-순서--구현-상태-한눈에-보기) 참고 — 계속 갱신되는 운영 기록.

**장애 대응 테스트(게임 데이) 카탈로그**는 [docs/resilience-testing.md](docs/resilience-testing.md) 참고 — 실행 결과는 `operations-log.md`에 기록.

## 관련 저장소

| 저장소 | 역할 |
|---|---|
| [slash-web](https://github.com/LikeLionTeam4/slash-web) | 웹 클라이언트 — React·Vite UI, S3/CloudFront 배포 |
| [slash-api](https://github.com/LikeLionTeam4/slash-api) | 코어 API — 인증, 작업 관리, 실행 위치 결정, DB 연동 |
| [slash-nlu](https://github.com/LikeLionTeam4/slash-nlu) | 자연어 분석 — slash 명령 파싱, 규칙·Kiwi 의도 분류, 인자 추출 |
| [slash-llm](https://github.com/LikeLionTeam4/slash-llm) | LLM 서비스 — Gemma 추론, 요약·대화 생성 |
| [slash-runner](https://github.com/LikeLionTeam4/slash-runner) | PC 작업 실행기 — PC 파일 검색, 상태 조회, 로컬 AI 실행·결과 전달 |
| **slash-infra** (현재) | 인프라 — Terraform(AWS), Helm·ArgoCD 배포 |
| [slash-docs](https://github.com/LikeLionTeam4/slash-docs) | 프로젝트 문서 — 아키텍처, API 계약, ERD, 회의록 |
