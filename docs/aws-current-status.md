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

VPC 1개(`10.8.0.0/16`), 가용 영역 2a/2c에 걸쳐 구성. 서브넷은 public/private-app/private-db
3계층 × AZ 2개, 총 6개. NAT Gateway는 AZ당 1개씩 이중화. private-db 서브넷은 인터넷 경로
없음 — S3만 Gateway Endpoint로 예외 허용.

| 서브넷 | CIDR | AZ |
| --- | --- | --- |
| public | `10.8.0.0/24`, `10.8.1.0/24` | 2a, 2c |
| private-app (EKS) | `10.8.10.0/24`, `10.8.11.0/24` | 2a, 2c |
| private-db (RDS/Valkey) | `10.8.20.0/24`, `10.8.21.0/24` | 2a, 2c |

보안그룹은 EKS용/DB용(EKS SG에서만 인바운드 허용)/Ollama EC2용 3개로 단순 구성.

## 컴퓨트

EKS 클러스터(`slash-eks-dev`, v1.36) 중심, 관리형 노드그룹에 `t3.medium` 3대
(desired 3 / min 2 / max 4). Karpenter 설치는 완료됐으나 현재 노드는 전부 관리형
노드그룹 소속 — 아직 실제 오토스케일링 트리거 이력 없음.

노드그룹은 EventBridge Scheduler로 매일 09시~21시(KST)만 desired 3으로 띄우고, 그
외 시간대는 desired/min 0으로 내려서 사용 시간에만 과금되게 관리 중(RDS도 동일
방식, 데이터베이스 항목 참고). 개발 단계에서 24시간 상시 가동 대비 비용을 절반
이상 줄이는 효과.

클러스터 위에는 ArgoCD, AWS Load Balancer Controller, External Secrets Operator,
metrics-server를 GitOps로 설치, 서비스 3개 배포 완료.

| 서비스 | 상태 |
| --- | --- |
| slash-api | 정상 (2 replica, Healthy) |
| slash-nlu | 정상 (2 replica, Healthy) |
| slash-llm | Ready 안 됨 (1 replica, Progressing) |

slash-llm 미기동 원인 확인 완료 — liveness(`/health`)와 readiness(`/ready`)가 분리돼
있고, `/ready`는 호출 대상인 Ollama 연결 상태를 그대로 반영해 계속 503 응답 중. 이
Ollama는 EKS 밖 별도 EC2(`g4dn.xlarge`)로 동작하는데 현재 stopped 상태 — 오늘 오전
수동으로 정지시킨 이력이 있고, EKS 노드그룹/RDS와 달리 Ollama는 자동 시작·정지
스케줄이 없어 켜기 전까진 계속 이 상태로 유지됨. 버그는 아니고, 지금 LLM 경로를
쓰지 않아 꺼둔 상태 — 다시 쓸 때 EC2부터 수동으로 켜면 됨.

## 컨테이너 레지스트리

ECR 리포지토리 3개(`slash-api`, `slash-nlu`, `slash-llm`), 전부 태그 불변(IMMUTABLE)
설정 — 배포 이미지 덮어쓰기 방지. 커밋 SHA 태그 각각 58/24/15개 누적, 꾸준한 배포
이력 확인.

## 데이터베이스

RDS는 PostgreSQL 16 계열(`db.t4g.small`, Multi-AZ) 1개 운영, 스토리지 20GB에서
필요시 자동 확장 설정. 캐시 레이어는 ElastiCache Valkey(`cache.t4g.micro`) 사용.
둘 다 private-db 서브넷 배치, EKS 내부에서만 접근 가능하며 외부 미노출.

RDS도 EKS 노드그룹과 동일하게 매일 09시~21시(KST)만 기동하고 나머지 시간은
정지시켜 비용을 관리 중(Valkey는 상시 가동). Ollama EC2만 이 자동 스케줄에서
빠져 있어 필요할 때 수동으로 켜고 끄는 방식(컴퓨트 항목 참고).

## 인그레스 / 도메인

프론트엔드는 CloudFront + S3로 `dev.sbsh.cloud` 서빙, API는 ALB로
`api.dev.sbsh.cloud` 연결. 두 도메인 모두 ACM 인증서 정상 발급, HTTPS 서비스 중.
로그인은 Cognito Hosted UI 사용.

## 모니터링

CloudWatch 알람 7개 구성(ALB 5xx/레이턴시, RDS CPU/스토리지, Valkey CPU/메모리/eviction),
확인 시점 기준 전부 정상 범위. 별도 대시보드로 통합 확인 가능, 알람 발생 시 SNS
경유 이메일 통보.

## CI/CD

각 서비스 저장소에서 GitHub Actions로 빌드 → ECR push 자동화, AWS 접근은 고정 키
대신 OIDC 임시 자격증명 방식. 이후 배포는 ArgoCD가 Git 변경 감지 후 자동 반영하는
GitOps 구조.
