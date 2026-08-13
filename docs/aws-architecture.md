# AWS 아키텍처 명세

Slash 프로젝트 전체(웹 프론트엔드 제외 백엔드 서비스군)를 AWS 위에 올리기 위한 설계 문서. `modules/frontend-hosting`처럼 실제 Terraform 구현의 기준점 역할을 한다. 아직 코드는 없고, 이 문서에 정리된 결정사항을 바탕으로 이후 `modules/`, `environments/`에 모듈을 추가해 나간다.

## 1. 개요 / 범위

- 대상 서비스: `slash-api`(코어 API), `slash-nlu`(자연어 분석), `slash-llm`(Gemma 추론), 그리고 이들을 잇는 공통 네트워크/DB/CI-CD 기반.
- `slash-agent`는 사용자 PC에서 로컬로 도는 컴포넌트라 AWS 인프라 범위에서 제외.
- 프론트엔드(`slash-web`)는 `modules/frontend-hosting`으로 이미 구현되어 있으므로 이 문서에서 재설계하지 않는다. 다만 API 인그레스 설계(§8)는 프론트엔드가 쓰는 CloudFront+ACM 패턴과 대칭이 되도록 맞춘다.
- 환경은 3단계로 나눈다 (자세한 역할은 §11):
  - **local** — 개인 맥북에서 직접 `terraform apply`하는 실험용. 지금까지 만든 `environments/local/*`이 여기 해당.
  - **dev** — prod와 거의 동일한 스펙을 유지하는 공유 테스트 서버. 아직 미구축.
  - **prod** — 실제 운영 환경. 아직 미구축.
- 아래 모든 리소스는 환경별로 복제 가능한 모듈 구조를 전제로 설계하고, 환경을 늘릴 때 값(인스턴스 크기, Multi-AZ 여부 등)만 다르게 넣는 방식을 목표로 한다.
- 예산은 "적당히 여유 있음" — 비용 최소화보다 가용성·확장성을 우선한다. 다만 GPU 노드처럼 비용이 크게 튀는 항목은 §12에 별도로 짚는다.

## 2. 리전 & 태깅 전략

- 기본 리전: `ap-northeast-2` (서울) — 기존 `environments/dev/frontend`와 동일.
- ACM 인증서 중 CloudFront에 붙는 것만 `us-east-1`이 강제되므로, 프론트엔드와 동일하게 `aws.us_east_1` provider alias를 유지한다. API용 ALB 인증서는 리전 제약이 없으므로 `ap-northeast-2`에서 발급한다.
- 네이밍 컨벤션은 기존 패턴을 그대로 따른다: 리소스명 `slash-<service>-<env>` (예: `slash-api-dev`, `slash-eks-dev`), `<env>`는 `local`/`dev`/`prod` 중 하나(§11).
- **계정은 하나**(부트캠프 공유 AWS 계정 — `a-student-*` 등 여러 팀이 같이 쓴다)를 local/dev/prod 전부가 함께 쓰고, 네이밍/태그로만 구분한다. 다른 팀 리소스와 섞이지 않도록 `slash-` 접두사를 절대 빠뜨리지 않는다. AWS CLI 프로필은 `slash-local`/`slash-dev`/`slash-prod`로 이름만 분리해뒀다(현재는 동일 IAM 사용자 자격증명을 가리키며, 팀에서 계정/사용자를 분리하기로 하면 프로필 값만 바꾸면 된다).
- 도메인은 가비아에서 구매한 `sbsh.cloud`를 쓴다. `environments/bootstrap`이 Route53 hosted zone을 관리하고, 가비아 네임서버를 그 zone의 NS 레코드로 변경해서 위임한다. 서브도메인 규칙은 prod=`sbsh.cloud`(apex), dev=`dev.sbsh.cloud`, local=`local.sbsh.cloud`.
- **태그는 리소스 탐색/비용 추적의 1차 수단**으로 쓴다. 콘솔·Cost Explorer·Resource Groups에서 태그로 바로 걸러볼 수 있어야 하므로, 모든 리소스에 아래 태그를 빠짐없이 붙인다:
  - `Project=slash` — 프로젝트 전체 공통
  - `Service=<service>` — `api` / `nlu` / `llm` / `network` / `eks` / `frontend` 등 어느 서비스·구성요소 소속인지
  - `Environment=<env>` — `dev` / `prod`
  - `ManagedBy=terraform` — 수동 생성 리소스와 구분
  - `Owner=<team>` — 이후 팀이 나뉘면 담당 파악용 (1인/단일팀 단계에서는 생략 가능)
  - `CostCenter=slash` — Cost Explorer에서 프로젝트 단위로 비용을 묶어 볼 때 사용 (Project와 값이 같아도, 별도 키로 두면 사내에 여러 프로젝트가 생겼을 때 필터링이 쉬움)
- 태그 누락을 막기 위해 각 provider 블록에 `default_tags`(공통 태그)를 설정하고, 리소스별로 필요한 태그만 추가로 얹는 방식을 기본으로 한다 — 프론트엔드 모듈처럼 매 리소스마다 `var.tags`를 일일이 넘기지 않아도 되게.
- AWS 콘솔의 **Resource Groups & Tag Editor**로 `Project=slash` 기준 전체 리소스를 한 화면에서 조회할 수 있게 하는 것을 태깅 전략의 성공 기준으로 삼는다.

## 3. State 관리

`environments/dev/frontend/main.tf`에는 현재 local backend를 쓰면서 "테스트 단계, 실 운영시 S3+DynamoDB로 이전 필요"라는 주석이 남아 있다. EKS 테스트 환경을 추가하는 시점에 이 이전을 함께 처리한다.

**결정: DynamoDB 없이 S3 단독으로 처리한다.** Terraform 1.10에서 S3 backend에 `use_lockfile` 옵션이 실험적으로 추가됐고 1.11에서 정식(GA) 기능이 되면서 `dynamodb_table`은 deprecated됐다. S3의 conditional write(`If-None-Match`)만으로 state에 `.tflock` 락 파일을 만들었다 지우는 방식이라 DynamoDB 없이도 동일하게 동시 apply를 막을 수 있다. 현재 설치된 Terraform이 1.15.8이라 바로 사용 가능.

- state 저장용 S3 버킷 1개 — 버저닝 활성화, 서버사이드 암호화, 퍼블릭 액세스 완전 차단. `environments/bootstrap/`에서 코드로 관리.
- 같은 `environments/bootstrap/`이 local/dev/prod가 공유하는 Route53 hosted zone(`sbsh.cloud`)도 함께 관리한다 — state 백엔드처럼 "모든 환경이 의존하는 최초 1회 자원"이라는 성격이 같아서 묶었다. 향후 ECR, CloudTrail처럼 환경 공통 자원이 늘어나면 같은 위치에 추가한다.
- 락은 `backend "s3" { ..., use_lockfile = true }` 설정만으로 처리되고, 별도 DynamoDB 테이블은 만들지 않는다.
- 부트스트랩 리소스(state용 S3 버킷) 자체의 state는 로컬로 둔다 — 아직 참조할 backend가 없는 최초 리소스라 생기는 닭-달걀 문제. `apply` 후 로컬 state 파일은 백업해두고, 유실돼도 버킷 이름이 계정 ID로 결정되는 값이라 `terraform import`로 복구 가능.
- 이후 만드는 모든 환경(예: `environments/dev/eks-test`)은 이 버킷을 `backend "s3"`로 참조하고, `required_version`을 `>=1.10.0`으로 올려서 `use_lockfile`을 쓴다.
- 기존 `environments/dev/frontend`도 같은 backend로 옮길지는 별도 확인 후 진행한다 (이번 범위 아님).

## 4. 네트워크 기반

- VPC 1개, 2개 AZ 기준 (`ap-northeast-2a`, `ap-northeast-2c`).
- **환경별 VPC CIDR은 간격을 둔 체계를 쓴다**(2026-08-12 결정): `local=10.0.0.0/16`, `dev=10.8.0.0/16`, `prod=10.16.0.0/16`(착수 시). 지금은 세 VPC가 서로 peering하지 않아 겹쳐도 기술적으론 무방하지만, 나중에 VPN/Transit Gateway/peering으로 환경 간 연결이 생겨도 라우팅 충돌이 없도록 미리 떨어뜨려둔다. `modules/network`의 `vpc_cidr`/`*_subnet_cidrs` 변수로 각 환경 root에서 오버라이드.
- 서브넷은 3-tier로 나눈다 — AZ당 public/private-app/private-db 각 1개씩 (총 6개 서브넷). RDS를 EKS 노드와 같은 private 서브넷에 두지 않고 분리하는 이유는 §7 참고.
  - **public** — ALB, NAT Gateway.
  - **private-app** — EKS 노드. NAT Gateway를 통해서만 아웃바운드.
  - **private-db** — RDS, Valkey(ElastiCache). 인터넷 기본 경로 없음(IGW/NAT 라우트 모두 미부여) — S3 접근은 NAT를 거치지 않고 §4-1의 S3 Gateway Endpoint로만 처리.
- 인터넷 게이트웨이는 1개(VPC당 1개면 충분 — AWS 리소스 특성상 여러 개를 둘 수 없음), NAT Gateway는 `modules/network`의 기본값으로 **AZ당 1개씩(가용성형)**을 쓴다 — dev/prod가 이 기본값 그대로. 예산에 여유가 있다는 전제([§1](#1-개요--범위))를 따른 결정. 다만 **local은 개인 실험용이라 `nat_gateway_per_az=false`로 오버라이드해 NAT 1개만 쓴다** (`environments/local/network`) — 3단계 도입 전 "dev부터 AZ당 1개" 방침을 local/dev+prod로 다시 나눈 것. 비용은 §12 참고.
- IAM은 EKS 워크로드가 AWS 리소스(RDS 접근용 Secrets Manager, ECR pull 등)에 접근할 때 IRSA(IAM Roles for Service Accounts)를 전제로 설계한다. 노드 IAM Role에 광범위한 권한을 주지 않는다.

### 4-1. 보안그룹 & VPC 엔드포인트

- 보안그룹은 최소 2종으로 시작한다.
  - **EKS SG** — 노드/파드 간 통신용. 클러스터 자체 생성 시 EKS가 만드는 SG와 별개로, 네트워크 계층에서 미리 준비해두는 baseline SG(같은 SG 내 전체 트래픽 허용 + 아웃바운드 전체 허용).
  - **DB SG** — RDS(5432)·Valkey(6379) 인바운드는 **EKS SG로부터의 트래픽만** 허용. 그 외 인바운드 없음, 퍼블릭 액세스 비활성.
- **S3 Gateway Endpoint**를 private-app/private-db 라우트테이블에 연결한다. private 서브넷에서 S3(state 버킷, 프론트엔드 정적 자산, ECR 이미지 레이어 캐시 등)에 접근할 때 NAT를 거치지 않아 NAT 데이터 처리 비용을 줄이고, private-db처럼 인터넷 경로 자체가 없는 서브넷도 S3만은 접근 가능하게 한다. Gateway Endpoint는 리전 내 무료.
- VPC Flow Log는 전용 S3 버킷에 저장한다 (버저닝 + 수명주기 정책, §10의 CloudTrail 버킷과 동일한 패턴). 트래픽 이상 탐지·보안그룹 규칙 디버깅용 1차 자료.

## 5. EKS 클러스터

`modules/eks`로 구현 완료 (범용 노드그룹 + ECR까지, PH-03의 1차 조각). GPU 노드그룹과 Karpenter 실제 설치는 다음 조각.

- 클러스터 1개 (`slash-eks-<env>`), private-app 서브넷에 워커 노드 배치. 버전은 명시하지 않고 AWS 기본값(그 시점 최신 지원 버전) 사용.
- 범용 노드그룹 EC2 3대(desired=3, min=2, max=4)로 시작 — 온디맨드, `network` 모듈의 `eks_security_group_id`를 launch template으로 명시 부착(EKS가 기본 생성하는 SG 대신 우리가 설계한 self-referencing SG를 쓰기 위해). 노드 IAM Role은 최소 권한(Worker/CNI/ECR ReadOnly/SSM)만 부여 — SSH 키 없이 SSM 세션으로 접속.
- **GPU 노드그룹(`slash-llm`용)은 만들지 않기로 확정(2026-08-13, [이슈 #12](https://github.com/LikeLionTeam4/slash-infra/issues/12))** — Ollama 런타임은 EKS 밖 독립 EC2로 대체한다. 이유와 상세는 §5-1.
- IRSA 활성화 — 클러스터 생성 시 AWS가 발급하는 클러스터 전용 OIDC 발급자를 `aws_iam_openid_connect_provider`로 등록해서, 파드가 자기 ServiceAccount 신원으로 IAM Role을 빌려쓸 수 있게 한다(§7-1의 Secrets Manager 접근이 이 경로를 씀). GitHub Actions용 OIDC provider(§9-1)와는 별개의 리소스.
- **오토스케일러는 Karpenter로 확정.** 단 이번 조각에는 컨트롤러용 IRSA Role(`karpenter_controller_role_arn`)만 준비 — Karpenter 자체(Helm 설치, NodePool/EC2NodeClass CRD)는 K8s 내부 리소스라 GitOps로 별도 설치. 노드에 붙일 인스턴스 프로필은 범용 노드그룹과 동일한 Role을 재사용.
- ALB Ingress Controller(§8)도 같은 이유로 이번 조각엔 없음 — Helm 설치는 GitOps, IRSA Role은 그 조각에서 준비.

### 5-1. LLM 추론 런타임 (Ollama, EC2 — EKS 밖)

**결정(2026-08-13, [이슈 #12](https://github.com/LikeLionTeam4/slash-infra/issues/12)): GPU 노드그룹 대신 독립 EC2 1대에 Ollama+Gemma3를 직접 설치한다.** 2026-08-12에는 `g4dn.xlarge` Spot + Karpenter 0-scale을 추천안으로 뒀었으나 아래 두 이유로 뒤집었다:

1. **콜드스타트**: Karpenter 0-scale은 스케일업마다 새 노드가 뜨는 구조라, 커스텀 AMI 없이는 Ollama 설치+`gemma3:4b` pull(수 GB)을 매번 반복해야 한다 — 5~10분+ 소요 추정, `slash-llm`의 기본 `LLM_TIMEOUT=120초`로는 사실상 타임아웃. 커스텀 AMI 빌드 파이프라인(Packer 등)은 지금 팀 규모/일정엔 과함.
2. **비용**: GPU 상시 가동은 On-demand 기준 월 ~$472, Spot이어도 ~$161~241 — `environments/bootstrap`의 계정 전체 월 $100 예산(§12)과 정면 충돌.

**아키텍처**: `slash-llm`(EKS, Helm/ArgoCD, `slash-api`/`slash-nlu`와 동일 GitOps 패턴)은 그대로 둔다 — 입력 검증·프롬프트 구성·동시성 제어(`LLM_MAX_CONCURRENT_REQUESTS`)·에러 정규화를 담당하는 실제 서비스 레이어라 EKS 표준 배포에서 뺄 이유가 없다. 그 뒤에서 호출하는 Ollama만 EKS 밖 EC2로 분리한다.

```
slash-web → slash-api → slash-llm(EKS) → Ollama(EC2, EKS 밖) → 역순 응답
```

- **네트워크**: `modules/network`에 `ollama` 보안그룹 신설 — `db` SG와 동일 패턴으로 `eks` SG에서만 11434 인바운드 허용. `private_app` 서브넷에 배치(NAT로 아웃바운드 인터넷 가능, 최초 설치 때 필요).
- **컴퓨트**: 신규 `modules/llm-runtime`(+ `environments/dev/llm-runtime`) — `g4dn.xlarge`, AWS Deep Learning Base GPU AMI(NVIDIA 드라이버 내장), SSM 세션 매니저용 IAM instance profile(SSH 키 불필요), `user_data`(cloud-init, 최초 부팅 1회만 실행)로 Ollama 설치 + `ollama pull gemma3:4b`. `Project=slash` 태그 필수(§12 예산 필터에 잡히게).
- **상태 보존**: 인스턴스는 stop/start로 운용한다(터미네이트 아님) — EBS 루트 볼륨이 유지돼 재기동 시 재설치·재pull이 없다. Private IP도 stop/start로는 안 바뀐다.
- **연결**: `helm/slash-llm/values-dev.yaml`의 `env.OLLAMA_URL`에 이 EC2의 private IP를 정적으로 채운다(`image.repository`처럼 정적 값 — 계정/환경이 바뀌면 수동 갱신, 별도 private DNS 존은 만들지 않는다).
- **스케줄링**: 초기엔 수동 stop/start. dev 트래픽 패턴이 확인되면 EventBridge Scheduler + SSM Automation으로 자동화를 후속 검토한다.
- **미해결**: `slash-llm`의 `/health`가 Ollama 연결 여부와 무관하게 항상 `{"status":"ok"}`를 반환한다(`main.py:76-78`) — Ollama가 죽어도 K8s가 파드를 정상으로 판단해 트래픽을 계속 흘려보낸다. `slash-llm` 팀에 `/health`가 Ollama 상태를 반영하도록 개선을 요청함(전달 완료, 2026-08-13) — 확정되면 readinessProbe 추가와 함께 반영.

**구현 체크리스트**:
- [x] `slash-llm` Dockerfile/CI/ECR push(PR #2, 2026-08-13 `dev` 머지) — `sha-78805a7108187751b1eb9283164c5071bd96f164` 이미지 push 확인
- [ ] `modules/network`에 `ollama` 보안그룹 추가
- [ ] `modules/llm-runtime` + `environments/dev/llm-runtime` 작성 → apply
- [ ] `helm/slash-llm/values-dev.yaml`에 `image.tag` + `env.OLLAMA_URL` 채우기
- [ ] EKS 파드 → Ollama EC2 실제 통신 검증(`curl`, 실제 요약 요청 왕복)

## 6. 컨테이너 레지스트리

`modules/ecr`로 구현 완료, `environments/bootstrap`에서 apply(2026-08-12 이전 — 아래 참고).

- 서비스별 ECR 리포지토리: `slash-api`, `slash-nlu`, `slash-llm`. `image_tag_mutability = IMMUTABLE` — 커밋 SHA 태그는 절대 안 바뀌니 덮어쓰기 자체를 막아둠.
- **계정 전체가 공유하는 리소스라 `environments/bootstrap`이 소유한다(2026-08-12, `modules/eks`에서 이전).** local/dev/prod가 같은 이미지(`sha-` 태그)를 dev에서 검증 후 prod로 그대로 승격해가며 쓰는 구조(§9-3)라, 애초에 환경별 리소스가 아니다. 원래는 `modules/eks`(즉 `environments/local/eks`)가 만들고 있었는데, `environments/dev/eks`를 그대로 apply하면 같은 이름(`slash-api` 등)의 리포지토리를 또 만들려다 충돌했을 것 — state 버킷·Route53 zone과 같은 이유로 `bootstrap`으로 옮겨서 해소했다. 마이그레이션은 `terraform import`(bootstrap 쪽)+`terraform state rm`(local/eks 쪽)로 실제 AWS 리소스는 건드리지 않고 state 소유권만 이전, `terraform plan`으로 양쪽 다 "0 to destroy" 확인.
- 수명주기 정책: 태그 없는 이미지는 7일 후, `sha-` 접두어 태그는 최근 10개만 남기고 자동 정리.
- **`mock-` 접두어 태그는 예외**다(예: `mock-20260811`) — 실제 서비스 저장소에 Dockerfile/CI가 없던 시점에 클러스터 없이 ECR push 파이프라인만 먼저 검증하려고 만든 placeholder 이미지용(`slash-infra` 저장소 내 `mock-services/`). `sha-` 규칙(개수 기준)과 겹치지 않게 별도 규칙으로 push 후 3일 뒤 자동 정리한다 — 공유 계정에 방치되는 이미지가 안 남게 하기 위함. 각 서비스 저장소에 실제 Dockerfile/CI가 생기면 `mock-services/`와 이 규칙 둘 다 정리 대상.

## 7. 데이터베이스

`modules/database`로 구현 완료 (RDS + Valkey + Secrets Manager, PH-02).

### 7-1. RDS PostgreSQL

인스턴스 1개, DB 2개(`slash_dev`, `slash_demo`)로 분리하는 구성을 dev 단계부터 그대로 쓴다. **Multi-AZ는 dev/prod부터 활성화**한다(§1의 "가용성·확장성 우선" 예산 전제를 따름) — **local은 NAT(§4)와 같은 이유로 단일 AZ로 확정**해서 §13의 미결정 항목을 해소했다(`environments/local/database`에서 `rds_multi_az = false`로 오버라이드, 모듈 기본값은 dev/prod에 맞춰 `true`).

- 마스터 비밀번호는 직접 만들지 않고 `manage_master_user_password = true`로 RDS가 자동 생성·로테이션까지 관리하는 Secrets Manager 시크릿을 쓴다 — 아래 "자격증명은 Secrets Manager로 관리"의 실제 구현.
- **DB 2개 분리는 Terraform이 전부 처리하지 못한다.** `db_name`으로 인스턴스 생성 시 첫 번째 DB(`slash_dev`)는 자동으로 생기지만, 두 번째 DB(`slash_demo`)는 실제 SQL(`CREATE DATABASE`)로 만들어야 하는데, RDS가 private-db 서브넷(인터넷 기본 경로 없음)에 있어서 **노트북에서 실행하는 Terraform은 애초에 그 인스턴스에 접속할 수 없다.** SSM 포트포워딩이나 EKS 안에서 도는 일회성 Job으로 만들어야 한다 — §13 TODO에 추가.

| 항목 | 값 | 비고 |
| --- | --- | --- |
| 엔진 | PostgreSQL 16 이상 | `gen_random_uuid()` 내장, `pgcrypto` 확장 불필요 |
| 인스턴스 클래스 | `db.t4g.small` (최소 `db.t4g.micro`) | Graviton, 시연 규모 부하에 충분 |
| 스토리지 | gp3 20GB + 오토스케일링 | 최소치로 시작, 스토리지 오토스케일링으로 여유 확보 |
| Multi-AZ | 활성 (local만 비활성) | dev/prod 공통, local은 비용 절감 위해 단일 AZ |
| 배치 위치 | private-db 서브넷 (§4) | 인터넷 기본 경로 없음 |
| 퍼블릭 액세스 | 비활성 | 인바운드는 EKS SG에서만 (§4-1 DB SG) |
| 자동 백업 | 7일 | |
| 데이터베이스 | `slash_dev` + `slash_demo` | 인스턴스 1개, DB 2개로 분리 — 별도 인스턴스를 늘리지 않고 환경을 나눔 |

- 자격증명은 Secrets Manager로 관리하고, `slash-api` 파드가 IRSA로 접근 (노드 IAM Role에는 권한을 주지 않음, §4).

### 7-2. Valkey (ElastiCache)

- 캐시/세션 레이어로 ElastiCache **Valkey**를 사용한다 (Redis OSS 포크, 라이선스 이슈 없이 호환).
- private-db 서브넷에 배치, DB SG와 동일한 원칙으로 EKS SG에서만 인바운드 허용.
- AUTH 토큰이 필요해서 `aws_elasticache_cluster`(단일 노드용, AUTH 미지원)가 아니라 `aws_elasticache_replication_group`을 쓴다 — 노드 1개(`num_cache_clusters = 1`, failover 대상 없음)라도 이 리소스여야 `transit_encryption_enabled`+`auth_token`이 붙는다.
- AUTH 토큰은 RDS처럼 자동 관리 기능이 없어서 `random_password`로 직접 생성해 Secrets Manager에 저장(엔드포인트·포트와 함께).
- 초기 규모는 시연 부하 기준 최소 노드 타입(`cache.t4g.micro`)으로 시작 — 정확한 사이징은 실사용 트래픽 확인 후 조정 (§13 TODO).

## 8. 인그레스 & 도메인

- AWS Load Balancer Controller로 ALB Ingress 구성, API 도메인(`api.dev.sbsh.cloud`, prod는 `api.sbsh.cloud`)에 대해 ACM 인증서(`ap-northeast-2`) 발급.
- 프론트엔드가 CloudFront+ACM(`us-east-1`)으로 서빙되는 것과 대칭 구조 — API는 리전 내 ALB+ACM으로 서빙.
- Route53에 API 도메인용 A(alias) 레코드 추가 (프론트엔드 모듈의 `aws_route53_record` 패턴과 동일).
- **IRSA Role(`modules/eks/alb_controller.tf`) + Helm 설치 + Ingress 스모크테스트까지 검증 완료**(2026-08-11) — 도메인 없이 internet-facing ALB를 띄워 mock 이미지 `/health` 응답까지 확인, 검증 후 destroy(운영 로그 참고). **ACM 인증서 발급 + `api.dev.sbsh.cloud` 같은 실제 도메인 연결은 아직**(dev 환경 자체가 미구축이라 §11).

## 9. CI/CD 파이프라인

- GitHub Actions: 각 서비스 저장소(`slash-api`, `slash-nlu`, `slash-llm`)에서 빌드 → 테스트 → ECR push.
- ArgoCD가 이 저장소의 `helm/` 디렉터리를 보고 EKS에 GitOps 방식으로 배포 — 이미지 태그 업데이트는 PR/커밋으로 반영(위치 결정은 §13 참고). **ArgoCD 설치 + "Git 커밋 → 자동 배포" 흐름 자체는 local 클러스터에서 검증 완료**(2026-08-11) — `argocd/` 디렉터리 참고, Application 3개(`helm/slash-api`·`slash-nlu`·`slash-llm` + `values-local.yaml`) 등록 후 `values-local.yaml` 커밋을 실제로 push해 자동 sync(스케일 업/다운 왕복) 확인, 검증 후 destroy(운영 로그 참고). dev 환경 자체가 미구축이라 상시 운영은 아직([이슈 #10](https://github.com/LikeLionTeam4/slash-infra/issues/10), dev 착수 시 `values-dev.yaml` 기준으로 전환).
- Helm chart 구조: `helm/`로 구현 완료(2026-08-11). 서비스별 디렉터리(`helm/slash-api/`, `helm/slash-nlu/`, `helm/slash-llm/`) + 환경별 values 파일(`values-local.yaml`/`values-dev.yaml`/`values-prod.yaml`)로 분리. `values-local.yaml`은 `mock-services/`가 push한 placeholder 이미지로 `helm lint`/`helm template`/`kubectl apply --dry-run=server` 검증까지 마침 — 실제 EKS apply는 검증 후 destroy(§운영 로그).
- **적용 범위: local 제외, dev부터 이 파이프라인 전체(GitHub Actions + ArgoCD)를 적용한다.** local은 개인이 직접 `terraform apply`/수동 배포하는 실험용이라 CI/CD 자동화가 필요 없다 (§11).

### 9-1. GitHub Actions → AWS 인증 (OIDC)

**결정: 고정 IAM 액세스 키를 GitHub Secrets에 저장하지 않고, OIDC federation으로 임시 자격증명을 발급받는다.** state 버킷 락(§3)에서 DynamoDB 대신 native lock을 택한 것과 같은 방향 — 오래 사는 고정 비밀보다 짧게 사는 위임 자격증명을 우선한다.

- GitHub Actions가 워크플로 실행마다 자체 OIDC 토큰(발급자 `token.actions.githubusercontent.com`)을 갖고, `aws-actions/configure-aws-credentials` 액션이 이 토큰으로 `AssumeRoleWithWebIdentity`를 호출해 몇 시간짜리 임시 자격증명을 받는다.
- **`aws_iam_openid_connect_provider`(발급자 `token.actions.githubusercontent.com`)는 우리가 만들지 않는다.** 2026-08-05 프론트엔드 CI/CD 작업 중 확인한 사실: 이 계정은 부트캠프 여러 팀이 공유하고 있고(`aws iam list-open-id-connect-providers`로 EKS OIDC provider가 60개 넘게 이미 있음을 확인), GitHub용 provider도 다른 팀(`Team1-front-github-oidc` 태그, 2025-08-01 생성)이 이미 만들어놨다. IAM OIDC provider는 계정에 URL당 1개만 등록 가능해서 우리가 새로 만들면 충돌한다 — Terraform에서 `aws_iam_openid_connect_provider` 리소스로 소유·관리하지 않고, `data "aws_iam_openid_connect_provider"`로 읽기 전용 참조만 한다(예시: `modules/frontend-cicd`). 이 provider의 생명주기(삭제 등)에는 절대 관여하지 않는다 — 다른 팀도 쓰고 있어서 지우면 그쪽 CI가 깨진다.
- 필요 리소스는 서비스별 IAM Role뿐이다(신뢰 정책을 `repo:LikeLionTeam4/<repo>:ref:refs/heads/<branch>`처럼 저장소·브랜치 단위로 제한). 백엔드는 ECR push 권한, 프론트엔드는 S3/CloudFront 권한(§9-2)으로 Role을 나눠서 최소 권한을 유지한다 — 같은 provider를 참조하는 Role을 서비스마다 여러 개 만드는 구조.
- **EKS의 IRSA용 OIDC provider(§5)와는 완전히 별개**다 — 발급자도, 신뢰 대상(저장소/브랜치 vs 클러스터의 ServiceAccount)도 다르다.
- ~~EKS/ECR을 만드는 PH-03 시점에 백엔드용 Role을 추가한다.~~ → **완료(2026-08-12)**: `modules/backend-cicd`로 `slash-api`/`slash-nlu`/`slash-llm` 각각 Role 생성, `environments/bootstrap`에서 apply(§9-3, §6 — ECR과 같은 이유로 계정 공용 소유). `frontend-cicd`와 달리 환경 접미사 없이 서비스당 Role 1개가 `dev`/`main` 브랜치를 동시에 신뢰 — ECR push 권한은 환경별로 다를 이유가 없어서.

### 9-2. 프론트엔드 배포 CI/CD (S3 + CloudFront)

`modules/frontend-cicd`로 구현 완료, local에서 apply·end-to-end 검증까지 마침(2026-08-05, 실제로 `local.sbsh.cloud`가 갱신되는 것까지 확인). 백엔드(§9)와 달리 컨테이너·EKS·ArgoCD를 전혀 쓰지 않는 훨씬 단순한 파이프라인이다 — `slash-web`은 Vite로 빌드되는 정적 사이트라 빌드 산출물을 S3에 올리고 CloudFront 캐시만 무효화하면 끝난다.

- 플로우: GitHub Actions에서 `npm run build` → OIDC로 임시 자격증명 획득 → `aws s3 sync`(`--delete`, `index.html` 제외하고 1년 캐시) → `index.html`만 별도로 `no-cache`로 업로드 → `cloudfront create-invalidation --paths "/index.html"`.
- **`index.html`을 마지막에, 별도로 올리는 이유**: Vite 빌드는 JS/CSS 파일명에 콘텐츠 해시가 붙어서 오래 캐시해도 안전하지만, `index.html`은 해시가 안 붙고 그 안에서 새 해시 파일들을 참조한다. 자산보다 `index.html`이 먼저 올라가면 아직 안 올라간 해시 파일을 참조하는 순간이 생겨 배포 중 404가 날 수 있다.
- IAM Role은 §9-1의 공유 OIDC provider를 참조하되, **백엔드용과는 별도**로 환경마다 하나씩(`slash-frontend-deploy-<env>`) 만든다 — 권한은 해당 환경의 버킷(`s3:PutObject/DeleteObject/ListBucket`)과 해당 CloudFront 배포(`cloudfront:CreateInvalidation`)로 한정, ECR 권한은 없음.
- **적용 범위: local부터 검증한다 (§9의 "local 제외, dev부터"와 다름).** §9의 "local 제외" 규정은 GitHub Actions+ArgoCD로 명시된 백엔드 GitOps 파이프라인 얘기고, 프론트엔드는 이미 떠 있는 `local/frontend`(EKS/DB처럼 매번 apply/destroy할 필요 없음)에 Role만 추가하면 되니 비용·시간 부담 없이 local에서 먼저 배선을 검증하고 dev/prod엔 버킷/배포 ID만 바꿔 재사용한다.
- **trust policy의 저장소 조건은 `StringEquals`가 아니라 `StringLike`+와일드카드를 쓴다.** `LikeLionTeam4` 조직은 GitHub OIDC의 "immutable IDs"가 켜져 있어서 실제 `sub` 클레임이 `repo:LikeLionTeam4/slash-web:ref:...`가 아니라 `repo:LikeLionTeam4@305683394/slash-web@1315812460:ref:...`처럼 조직·저장소명 뒤에 불변 숫자 ID가 붙어 나온다(2026-08-05 CloudTrail로 확인, `docs/operations-log.md` §4 참고). 숫자 ID를 하드코딩하는 대신 이름 뒤에 와일드카드(`repo:<org>*/<repo>*:ref:refs/heads/<branch>`)를 둬서 ID 유무와 무관하게 매칭한다.
- **현재 타겟 브랜치는 `dev`, 원래 의도는 `main`이었다.** `slash-web`의 `main`은 아직 `README.md`뿐인 빈 스텁 브랜치라(첫 시도 때 `npm ci`가 빌드할 앱 자체가 없어서 실패) 실제 개발이 이뤄지는 `dev`를 임시로 타겟팅했다. 팀이 `dev`→`main` 첫 정식 릴리스를 하면 `modules/frontend-cicd` 호출부(`environments/local/frontend`)의 `github_branch`와 `slash-web`의 워크플로 트리거를 `main`으로 되돌려야 한다(코드에 TODO로 남겨둠).
- 워크플로 파일은 `slash-web` 저장소에 있다(`slash-infra`가 아님) — `.github/workflows/deploy-local.yml`.

### 9-3. dev/prod 배포 트리거 및 브랜치 전략

**결정(2026-08-12, [이슈 #17](https://github.com/LikeLionTeam4/slash-infra/issues/17)):** dev는 `dev` 브랜치 push마다 자동 배포(승인 없음), prod는 `main` push/merge 트리거 + GitHub Environment(`production`) 필수 리뷰어로 배포 전 승인 게이트를 둔다. §9-2의 프론트엔드 CI/CD가 이미 갖고 있던 "dev→main 첫 릴리스하면 main으로 되돌릴 것" TODO와 같은 방향이라 백엔드도 동일 패턴을 따른다.

- `slash-api`/`slash-nlu`/`slash-llm` 세 저장소의 `main` 브랜치에 `required_linear_history`(선형 히스토리 강제, `allow_force_pushes`/`allow_deletions`도 함께 비활성) 브랜치 보호 규칙 적용 완료(2026-08-12, GitHub 저장소 설정 — Terraform 관리 대상 아님). 목적: `dev`에서 이미 검증된 이미지(`sha-` 커밋 태그, IMMUTABLE, §6)를 머지 커밋으로 SHA를 바꾸지 않고 그대로 prod로 승격하기 위함 — PR 머지는 Squash/Rebase만 가능해짐(일반 Merge commit 방식 차단).
- `production` Environment(필수 리뷰어)는 저장소 설정에서 생성하는 것으로, 실제 배포 워크플로 자체는 [이슈 #11](https://github.com/LikeLionTeam4/slash-infra/issues/11)(각 서비스 실제 Dockerfile 대기)이 풀려야 착수 가능 — 지금은 자리만 마련해둔 상태.
- 지금은 세 저장소 다 `main`이 `dev`보다 9~35개 커밋 뒤처진 사실상 미사용 브랜치라 이 변경이 팀 작업에 즉시 영향을 주진 않는다. 첫 `dev→main` 릴리스 시점에 팀 공지가 필요 — [이슈 #18](https://github.com/LikeLionTeam4/slash-infra/issues/18)에서 추적.
- `environments/dev/frontend`(→ `dev.sbsh.cloud`) 착수는 보류 — 백엔드 dev가 실제로 QA 가능해지고 프론트가 dev API를 호출할 필요가 생기는 시점에 팀 합의 후 진행(§9-2의 `local/frontend`와는 별개).

## 10. 옵저버빌리티 (CloudWatch / CloudTrail)

Terraform 밖에서 별도로 작업할 필요는 없다 — AWS provider가 CloudWatch/CloudTrail 리소스를 그대로 지원하므로 다른 모듈과 동일하게 관리한다. **CloudTrail은 `environments/bootstrap`, CloudWatch 알람은 `modules/observability`(환경별)로 구현 완료** — 둘의 위치가 다른 이유는 아래 참고.

- **CloudWatch** (`modules/observability`, PH-05 1차 조각)
  - RDS CPU 사용률(80% 초과)·여유 스토리지(2GB 미만) 알람 2개 + 알림용 SNS 토픽. `alarm_email` 변수로 이메일 구독 선택 가능.
  - **ALB 5xx 비율, GPU 노드 사용률 알람은 이번 조각에 없다** — ALB Ingress·GPU 노드그룹 자체가 아직 없어서(§8, §5) 감시할 대상이 없음. 그것들이 생기면 이 모듈에 추가.
  - 애플리케이션 로그 그룹(`aws_cloudwatch_log_group`, 예: `/eks/slash-api-dev`)은 아직 안 만듦 — 실제로 로그를 그 그룹에 밀어넣으려면 Fluent Bit 같은 로그 수집 에이전트가 클러스터 안에서 돌아야 하는데, 그 설치는 ALB Controller/Karpenter와 같은 이유로 GitOps 몫이라 로그 그룹만 먼저 만들어봐야 실익이 적어 미룸.
- **CloudTrail** (`environments/bootstrap`)
  - 계정 전체 API 호출 감사용으로 트레일 1개(`aws_cloudtrail`)를 만들고, 로그는 전용 S3 버킷(버저닝 + 수명주기 정책, 잠정 90일 후 만료)에 적재.
  - **왜 환경별 모듈이 아니라 bootstrap에 두나**: CloudTrail은 계정 전체를 감사하는 거라 local/dev/prod가 각자 만들면 같은 계정 안에 트레일이 중복된다 — state 버킷·Route53 zone처럼 "계정당 한 번만" 만드는 자원이라 bootstrap이 자연스러운 자리. 반대로 CloudWatch 알람은 특정 환경의 RDS/EKS를 가리켜야 해서 환경별로 필요.
  - 단일 리전 트레일로 충분, 계정이 여러 개로 늘어나면 organization trail 전환을 고려.

## 11. 환경 전략

local/dev/prod 3단계로 나눈다. **결정(2026-08-12): 팀 전체가 계정 하나(`727646470302`)의 인프라를 공유한다** — local도 예외가 아니다. §2의 "계정은 하나"가 곧 실제 운영 방식이고, 아래 표의 local 행도 이에 맞게 갱신했다(원래는 "local은 팀원마다 다른 계정"으로 설계했었으나, 실제로는 처음부터 전부 이 계정으로 진행돼왔음을 확인). [README §다른 AWS 계정에서 시작하기](../README.md#다른-aws-계정에서-시작하기-팀원용)는 이론상 다른 계정으로 시작하고 싶은 경우를 위해 남겨두지만, 팀의 기본 운영 방식은 아니다.

| 환경 | 역할 | 스펙 | 계정 | 상태 |
| --- | --- | --- | --- | --- |
| **local** | 개인 맥북에서 `terraform apply`하는 실험용 — 모듈 변경을 실제 AWS에서 검증 | 최소 구성 (`environments/local/*` 그대로) | **이 계정(`727646470302`)을 팀 전체가 공유**(2026-08-12 확정) — `slash-local` AWS CLI 프로필도 같은 계정을 가리킴. ECR처럼 계정 전체가 공유하는 자원은 `environments/bootstrap`으로 소유권을 모아 환경 간 충돌을 막는다(§6) | `network`/`frontend`/`eks`(검증용, apply→destroy 반복) 구축, RDS는 다음 단계 |
| **dev** | prod와 거의 동일한 스펙을 유지하는 공유 테스트 서버 — 팀 전체가 QA에 사용 | prod와 동일 모듈, 동일 값(인스턴스 크기 등) | **이 계정(`727646470302`)으로 확정**(2026-08-11, [이슈 #13](https://github.com/LikeLionTeam4/slash-infra/issues/13)) — prod와 같은 계정을 공유, `Environment=dev` 태그와 리소스명 접미사(`-dev`)로만 구분 | 미구축 — 착수 대기 |
| **prod** | 실제 운영 환경 | Multi-AZ, 가용성 우선 | **이 계정(`727646470302`)으로 확정.** `sbsh.cloud` 도메인 위임(가비아 NS)이 이미 이 계정의 Route53 zone을 가리키고 있어서, prod의 apex 도메인(§2)도 결국 이 계정에 있어야 한다 — 별도 prod 계정으로 나중에 재위임하지 않기로 함. 나머지 담당자는 이 계정에 IAM 사용자만 추가 | 미구축 |

- local에서 검증된 모듈을 그대로 dev/prod에 재사용한다 — 모듈 코드 자체는 세 환경이 동일하고, `environments/<env>/` root의 변수 값만 다르다.
- local이 dev/prod와 값만 다른 게 아니라 **아예 빠지는 것도 있다**: NAT Gateway는 local만 1개(§4), RDS Multi-AZ는 dev/prod만 활성화(§7-1), **백엔드 CI/CD 파이프라인(GitHub Actions + ArgoCD, §9)은 dev부터만 적용**하고 local은 수동 배포로 충분하다. 단 **프론트엔드 CI/CD(§9-2)는 예외** — local부터 검증한다.
- prod 확장 시 EKS 구성 방식 두 가지 중 선택 필요 (아직 미결정, 다음 라운드 인터뷰 대상):
  - **네임스페이스 분리**: 같은 EKS 클러스터 안에서 `dev`/`prod` 네임스페이스로 나눔 — 비용 절감, 격리는 약함.
  - **클러스터 분리**: 환경별로 별도 EKS 클러스터 — 격리는 강하지만 비용·운영 부담 증가.

## 12. 비용 관점

예산에 영향이 큰 순서대로:

1. **EKS 컨트롤플레인 고정비** — 클러스터당 시간당 과금, 환경을 늘릴수록 누적.
2. **LLM 런타임 EC2(`g4dn.xlarge`, §5-1)** — GPU 인스턴스라 시간당 비용이 큼(On-demand ~$0.65/h, Spot ~$0.22~0.33/h, ap-northeast-2 기준). 상시 가동은 월 $100 예산과 충돌해 stop/start 스케줄로 운용한다.
3. **NAT Gateway** — dev/prod는 AZ당 1개(§4)라 시간당 과금 + 데이터 처리 비용이 2배로 발생. local은 1개로 아낀다. S3 접근은 Gateway Endpoint(§4-1)로 우회해 데이터 처리 비용 일부는 줄인다.
4. **RDS Multi-AZ** — dev/prod는 활성화(§7-1)라 인스턴스 비용이 2배로 발생 — 기존 "prod만 Multi-AZ" 가정에서 변경됨.
5. **Valkey(ElastiCache)** — RDS와 별개로 상시 과금되는 노드. 최소 타입으로 시작해도 24시간 켜져 있는 비용이 누적됨.
6. **CloudTrail/CloudWatch/VPC Flow Log 보관** — 보관 기간이 길어지거나 로그량이 많아지면 S3/CloudWatch Logs 비용이 누적되므로 수명주기 정책으로 관리.

**안전망**: `environments/bootstrap`의 `aws_budgets_budget.monthly_cost`(2026-08-12 apply)가 `Project=slash` 태그 기준 월 $100 한도로 실지출 80%/100%·예상지출 100% 시 이메일 알림을 보낸다(계정을 다른 팀과 공유하고 있어서 태그로 스코핑, `docs/operations-log.md` §8-3 참고). $100은 시작값이라 사용 패턴이 바뀌면(dev 상시 운영, prod 착수 등) 조정 필요.

## 13. 미결정 사항 / TODO

다음 인터뷰 라운드에서 채워야 할 항목:

- ~~dev 환경의 계정 구조~~ → prod와 같은 계정(`727646470302`)을 공유하는 것으로 확정(2026-08-11, §11, [이슈 #13](https://github.com/LikeLionTeam4/slash-infra/issues/13)). 다음 단계는 `environments/dev/` 착수
- `slash_demo` DB를 실제로 어떻게 만들지 — **추천(2026-08-12): EKS 안의 일회성 Job.** SSM 포트포워딩용 별도 bastion EC2를 새로 세우는 것보다, 이미 만드는 EKS 노드가 private-app 서브넷에서 DB SG로 가는 경로를 이미 갖고 있어(§4-1) 추가 리소스·보안 표면 없이 `postgres` 클라이언트 이미지로 `CREATE DATABASE slash_demo;` 한 번 실행하고 지우면 된다. dev DB를 실제로 쓰기 시작하는 시점에 적용
- Karpenter 실제 설치(Helm, NodePool/EC2NodeClass) — IRSA Role은 `eks` 모듈에 준비됐지만 한 번도 설치해본 적 없음(§5)
- ~~ALB Ingress Controller 실제 설치~~ → IRSA Role apply + Helm 설치 + mock 이미지로 실제 ALB 응답까지 검증 완료(2026-08-11, §8). 도메인/ACM 연결과 상시 운영은 dev 환경 구축 후([이슈 #10](https://github.com/LikeLionTeam4/slash-infra/issues/10))
- ~~ArgoCD 설치 및 GitOps 저장소 구조~~ → `helm/` 위치 결정 + local 클러스터에서 ArgoCD 설치·GitOps 자동 배포 왕복 검증까지 완료(2026-08-11, §9, [이슈 #10](https://github.com/LikeLionTeam4/slash-infra/issues/10)). dev 계정 구조가 정해지고 dev 환경이 실제로 구축되면 같은 `argocd/` manifest를 `values-dev.yaml` 기준으로 옮겨 상시 운영 전환
- ~~GPU 인스턴스 정확한 타입/개수~~ → **결정 변경(2026-08-13, [이슈 #12](https://github.com/LikeLionTeam4/slash-infra/issues/12)): GPU 노드그룹 대신 독립 EC2(`g4dn.xlarge`) 1대, stop/start로 운용.** 상세는 §5-1. 실제 Gemma 모델 크기(2B/7B/9B)에 따라 16GB VRAM으로 부족할 수 있어 `slash-llm` 팀 확인은 여전히 필요
- `slash-nlu`의 컴퓨트 요구사항 (CPU 규모, 메모리) — Kiwi 기반이라 GPU는 불필요할 것으로 추정하나 확정 필요
- prod 환경의 네임스페이스 분리 vs 클러스터 분리 (§11) — **추천(2026-08-12): 클러스터 분리.** VPC·RDS·Cognito는 이미 dev/prod를 완전히 분리하기로 했는데 EKS 컨트롤플레인만 공유하면 일관성이 깨지고, dev의 실수(예: 2026-08-12에 겪은 orphan ALB류)가 prod 워크로드에 물리적으로 영향을 못 주게 격리하는 게 안전하다. 클러스터당 월 ~$75 추가 비용은 있지만 이미 dev용 클러스터를 별도로 두기로 한 시점에서 증분은 크지 않음
- ~~Helm chart를 slash-infra 내부에 둘지, 별도 저장소로 분리할지~~ → **결정: `slash-infra` 내부(`helm/`)로 확정**(2026-08-11). Terraform이 만드는 IRSA Role ARN 등과 값이 맞물려 있어 같은 저장소/같은 PR로 바꾸는 게 안전하고, 지금 규모(단일 담당자, 남은 기간 짧음)에서 저장소를 나누는 비용이 더 크다고 판단. CI가 이미지 태그를 자주 커밋하기 시작해 git log가 지저분해지면 그때 분리 재검토
- CloudTrail 로그 보관 기간(지금은 90일 잠정 기본값), CloudWatch 알람의 실제 임계값(지금은 CPU 80%/스토리지 2GB 잠정값) — 트래픽 실측 후 조정
- ALB Ingress·GPU 노드그룹이 생기면 그 알람(5xx 비율, GPU 사용률)을 `modules/observability`에 추가
- `Owner` 태그를 지금부터 붙일지, 팀이 나뉘는 시점부터 붙일지
- Valkey(ElastiCache) 정확한 노드 타입/개수 (§7-2, 캐시 대상 데이터와 세션 규모 확정 후)
