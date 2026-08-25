# AWS 인프라 구축 현황

AWS 계정에 실제로 떠 있는 리소스 정리, 2026-08-24 기준. 설계 배경·결정 이유는
`aws-architecture.md`, 리소스별 관리 환경은 `resource-ownership.md` 참고. 여기서는
현재 가동 중인 리소스만 다룸.

리전은 서울(`ap-northeast-2`), CloudFront 인증서만 규정상 `us-east-1`에서 발급. 환경은
`dev`만 상시 운영 중, `local`은 EKS 모듈 테스트용으로만 유지. `prod`는 아직 착수 전.
계정은 부트캠프 공유 계정이라, 아래 내용은 `slash-` 이름이 붙은 리소스만 추림.

## 목차

- [네트워크](#네트워크)
- [컴퓨트](#컴퓨트)
- [컨테이너 레지스트리](#컨테이너-레지스트리)
- [데이터베이스](#데이터베이스)
- [인그레스 / 도메인](#인그레스--도메인)
- [모니터링](#모니터링)
- [CI/CD](#cicd)

## 네트워크

- VPC 1개(`10.8.0.0/16`), 가용 영역 2a/2c에 걸쳐 구성
- 서브넷 6개 (public/private-app/private-db 3계층 × AZ 2개)

  | 서브넷 | CIDR | AZ |
  | --- | --- | --- |
  | public | `10.8.0.0/24`, `10.8.1.0/24` | 2a, 2c |
  | private-app (EKS) | `10.8.10.0/24`, `10.8.11.0/24` | 2a, 2c |
  | private-db (RDS/Valkey) | `10.8.20.0/24`, `10.8.21.0/24` | 2a, 2c |

- NAT Gateway: AZ당 1개씩 이중화
- private-db 서브넷: 인터넷 경로 없음, S3만 Gateway Endpoint로 예외 허용
- 보안그룹 3개: EKS용 / DB용(EKS SG에서만 인바운드 허용) / Ollama EC2용

## 컴퓨트

**EKS**

- 클러스터 `slash-eks-dev` (v1.36), 관리형 노드그룹 `t3.medium` 3대 (desired 3 / min 2 / max 4)
- Karpenter 설치 완료, 다만 현재 노드는 전부 관리형 노드그룹 소속 — 실제 오토스케일링 트리거 이력은 아직 없음
- 클러스터 위 GitOps로 설치된 구성요소: ArgoCD, AWS Load Balancer Controller, External Secrets Operator, metrics-server
- **비용 관리**: EventBridge Scheduler로 매일 09시~21시(KST)만 desired 3, 그 외 시간대는 desired/min 0으로 축소 (RDS도 동일 방식, 데이터베이스 항목 참고) — 24시간 상시 가동 대비 절반 이상 절감

**배포 서비스 상태**

| 서비스 | 상태 |
| --- | --- |
| slash-api | 정상 (2 replica, Healthy) |
| slash-nlu | 정상 (2 replica, Healthy) |
| slash-llm | Ready 안 됨 (1 replica, Progressing) |

slash-llm은 현재 기능상 연결되는 부분이 없어 Ollama EC2(`g4dn.xlarge`)를 정지시켜둔 상태 —
readiness(`/ready`)가 Ollama 연결 여부를 그대로 반영해 503을 주는 것으로, 버그가 아니라
의도된 상태. 다시 쓸 때 EC2만 켜면 정상화됨.

## 컨테이너 레지스트리

ECR 리포지토리 3개, 전부 태그 불변(IMMUTABLE) 설정 — 배포 이미지 덮어쓰기 방지.
현재 클러스터에 떠 있는 태그는 아래와 같음(=지금 서비스 중인 커밋).

| 리포지토리 | 현재 배포 태그 |
| --- | --- |
| `slash-api` | `sha-3d0eadae` |
| `slash-nlu` | `sha-69c6708f` |
| `slash-llm` | `sha-27d76da2` |

## 데이터베이스

- **RDS**: PostgreSQL 16 계열(`db.t4g.small`, Multi-AZ) 1개, 스토리지 20GB에서 필요시 자동 확장
- **Valkey (ElastiCache)**: `cache.t4g.micro`, 상시 가동
- 둘 다 private-db 서브넷 배치, EKS 내부에서만 접근 가능하며 외부 미노출
- **비용 관리**: RDS는 EKS 노드그룹과 동일하게 매일 09시~21시(KST)만 기동, 나머지 시간은 정지 (Valkey는 상시 가동, Ollama EC2만 자동 스케줄 없이 수동 운영 — 컴퓨트 항목 참고)

## 인그레스 / 도메인

- 프론트엔드: CloudFront + S3 → `dev.sbsh.cloud`
- API: ALB → `api.dev.sbsh.cloud`
- 두 도메인 모두 ACM 인증서 정상 발급, HTTPS 서비스 중
- 로그인: Cognito Hosted UI

## 모니터링

CloudWatch 알람 7개, 확인 시점 기준 전부 정상 범위:

- ALB: 5xx 비율, 응답 지연(latency)
- RDS: CPU, 여유 스토리지
- Valkey: CPU, 메모리, eviction

별도 대시보드로 통합 확인 가능, 알람 발생 시 SNS 경유로 이메일 통보.

## CI/CD

1. 각 서비스 저장소에서 GitHub Actions로 빌드
2. AWS 접근은 고정 키 대신 OIDC 임시 자격증명 방식으로 처리
3. 빌드된 이미지를 ECR에 push
4. ArgoCD가 Git 변경을 감지해 클러스터에 자동 반영 (GitOps)
