# AWS 아키텍처 명세

Slash 프로젝트 전체(웹 프론트엔드 제외 백엔드 서비스군)를 AWS 위에 올리기 위한 설계 문서. `modules/frontend-hosting`처럼 실제 Terraform 구현의 기준점 역할을 한다. 아직 코드는 없고, 이 문서에 정리된 결정사항을 바탕으로 이후 `modules/`, `environments/`에 모듈을 추가해 나간다.

## 1. 개요 / 범위

- 대상 서비스: `slash-api`(코어 API), `slash-nlu`(자연어 분석), `slash-llm`(Gemma 추론), 그리고 이들을 잇는 공통 네트워크/DB/CI-CD 기반.
- `slash-agent`는 사용자 PC에서 로컬로 도는 컴포넌트라 AWS 인프라 범위에서 제외.
- 프론트엔드(`slash-web`)는 `modules/frontend-hosting`으로 이미 구현되어 있으므로 이 문서에서 재설계하지 않는다. 다만 API 인그레스 설계(§8)는 프론트엔드가 쓰는 CloudFront+ACM 패턴과 대칭이 되도록 맞춘다.
- 환경은 **dev를 먼저 구축**한다. 아래 모든 리소스는 환경별로 복제 가능한 모듈 구조를 전제로 설계하고, prod로 확장할 때 값(인스턴스 크기, Multi-AZ 여부 등)만 다르게 넣는 방식을 목표로 한다.
- 예산은 "적당히 여유 있음" — 비용 최소화보다 가용성·확장성을 우선한다. 다만 GPU 노드처럼 비용이 크게 튀는 항목은 §11에 별도로 짚는다.

## 2. 리전 & 계정 기준

- 기본 리전: `ap-northeast-2` (서울) — 기존 `environments/dev/frontend`와 동일.
- ACM 인증서 중 CloudFront에 붙는 것만 `us-east-1`이 강제되므로, 프론트엔드와 동일하게 `aws.us_east_1` provider alias를 유지한다. API용 ALB 인증서는 리전 제약이 없으므로 `ap-northeast-2`에서 발급한다.
- 네이밍/태그 컨벤션은 기존 패턴을 그대로 따른다:
  - 리소스명: `slash-<service>-<env>` (예: `slash-api-dev`, `slash-eks-dev`)
  - 공통 태그: `Project=slash`, `Service=<service>`, `Environment=<env>`, `ManagedBy=terraform`

## 3. State 관리

`environments/dev/frontend/main.tf`에는 현재 local backend를 쓰면서 "테스트 단계, 실 운영시 S3+DynamoDB로 이전 필요"라는 주석이 남아 있다. 백엔드 서비스 인프라를 추가하는 시점에 이 이전을 함께 처리한다:

- state 저장용 S3 버킷 1개 (버저닝 활성화)
- state locking용 DynamoDB 테이블 1개
- 이 둘은 모든 환경/모듈이 공유하는 "부트스트랩" 리소스이므로, 별도의 최소 구성(`environments/bootstrap/` 같은) 또는 수동 1회 생성 후 backend 설정으로 참조하는 방식 중 하나를 다음 단계에서 정한다.

## 4. 네트워크 기반

- VPC 1개, 2개 AZ 기준 (`ap-northeast-2a`, `ap-northeast-2c`).
- AZ당 public/private 서브넷 각 1개씩 (총 4개 서브넷).
  - public: ALB, NAT Gateway
  - private: EKS 노드, RDS
- NAT Gateway는 트레이드오프가 있음:
  - **비용형(NAT 1개)**: 월 비용 절반, 하지만 해당 AZ 장애 시 private 서브넷 전체가 아웃바운드 불가
  - **가용성형(AZ당 NAT 1개)**: 비용 2배, AZ 장애에 견고
  - dev는 **비용형(NAT 1개)**, prod는 **가용성형(AZ당 1개)**을 기본값으로 제안. 예산에 여유가 있다는 전제이므로 처음부터 가용성형으로 가도 무리는 없다 — 실제 구현 시점에 재확인.
- IAM은 EKS 워크로드가 AWS 리소스(RDS 접근용 Secrets Manager, ECR pull 등)에 접근할 때 IRSA(IAM Roles for Service Accounts)를 전제로 설계한다. 노드 IAM Role에 광범위한 권한을 주지 않는다.

## 5. EKS 클러스터

- 클러스터 1개 (`slash-eks-dev`), private 서브넷에 워커 노드 배치.
- 노드그룹 2종:
  - **범용 노드그룹** — `slash-api`, `slash-nlu`, ArgoCD, 기타 클러스터 애드온용. 온디맨드, 오토스케일링 (최소/최대는 실사용 부하 보고 결정).
  - **GPU 노드그룹** — `slash-llm`(Gemma 추론) 전용. `g4dn.xlarge` 또는 `g5.xlarge` 계열로 시작, NVIDIA device plugin 필요. 상시 켜두면 비용이 크므로 오토스케일링(0으로 축소 가능한 구성)을 강하게 권장 — 콜드스타트(모델 로딩 시간)와 비용의 트레이드오프는 실제 트래픽 패턴을 보고 조정.
- IRSA 활성화, 클러스터 오토스케일러 또는 Karpenter 중 하나를 붙인다 (Karpenter가 GPU/스팟 혼합 노드 관리에 더 유연하므로 우선 후보).

## 6. 컨테이너 레지스트리

- 서비스별 ECR 리포지토리: `slash-api`, `slash-nlu`, `slash-llm`.
- 이미지 태그는 커밋 SHA 기준, 수명주기 정책으로 오래된 이미지 자동 정리.

## 7. 데이터베이스

- `slash-api` 전용 RDS PostgreSQL.
- dev: 단일 인스턴스 (Multi-AZ 없음), private 서브넷의 DB 서브넷 그룹에 배치.
- prod: Multi-AZ 옵션 활성화 — 장애 시 자동 failover.
- 자격증명은 Secrets Manager로 관리하고, `slash-api` 파드가 IRSA로 접근.

## 8. 인그레스 & 도메인

- AWS Load Balancer Controller로 ALB Ingress 구성, API 도메인(`api.dev.slash.example.com` 등, 실제 도메인은 §12 참고)에 대해 ACM 인증서(`ap-northeast-2`) 발급.
- 프론트엔드가 CloudFront+ACM(`us-east-1`)으로 서빙되는 것과 대칭 구조 — API는 리전 내 ALB+ACM으로 서빙.
- Route53에 API 도메인용 A(alias) 레코드 추가 (프론트엔드 모듈의 `aws_route53_record` 패턴과 동일).

## 9. CI/CD 파이프라인

- GitHub Actions: 각 서비스 저장소(`slash-api`, `slash-nlu`, `slash-llm`)에서 빌드 → 테스트 → ECR push.
- ArgoCD가 별도 Git 저장소(또는 slash-infra 내 `helm/` 디렉터리)의 Helm chart를 보고 EKS에 GitOps 방식으로 배포 — 이미지 태그 업데이트는 PR/커밋으로 반영.
- Helm chart 구조 제안: 서비스별 디렉터리(`helm/slash-api/`, `helm/slash-nlu/`, `helm/slash-llm/`), 환경별 values 파일(`values-dev.yaml`, `values-prod.yaml`)로 분리.

## 10. 환경 전략

- dev를 먼저 구현 완료.
- prod 확장 시 두 가지 방식 중 선택 필요 (아직 미결정, 다음 라운드 인터뷰 대상):
  - **네임스페이스 분리**: 같은 EKS 클러스터 안에서 `dev`/`prod` 네임스페이스로 나눔 — 비용 절감, 격리는 약함.
  - **클러스터 분리**: 환경별로 별도 EKS 클러스터 — 격리는 강하지만 비용·운영 부담 증가.

## 11. 비용 관점

예산에 영향이 큰 순서대로:

1. **EKS 컨트롤플레인 고정비** — 클러스터당 시간당 과금, 환경을 늘릴수록 누적.
2. **GPU 노드(slash-llm)** — 온디맨드 g4dn/g5는 시간당 비용이 큼. 스팟 인스턴스 활용이나 오토스케일 0-scale로 완화 가능하지만 콜드스타트 트레이드오프 있음.
3. **NAT Gateway** — AZ당 구성 시 시간당 과금 + 데이터 처리 비용이 배로 늘어남 (§4 참고).
4. **RDS Multi-AZ** — prod에서 활성화 시 인스턴스 비용 2배.

## 12. 미결정 사항 / TODO

다음 인터뷰 라운드에서 채워야 할 항목:

- 실제 프로덕션 도메인명 (`dev.slash.example.com`은 현재 placeholder)
- GPU 인스턴스 정확한 타입/개수, 예상 동시 요청 수 (Gemma 모델 크기에 따라 필요 VRAM이 달라짐)
- `slash-nlu`의 컴퓨트 요구사항 (CPU 규모, 메모리) — Kiwi 기반이라 GPU는 불필요할 것으로 추정하나 확정 필요
- prod 환경의 네임스페이스 분리 vs 클러스터 분리 (§10)
- state 부트스트랩 리소스(S3+DynamoDB)를 별도 Terraform 루트로 만들지, 수동 1회 생성으로 할지
- Helm chart를 slash-infra 내부에 둘지, 별도 저장소로 분리할지
