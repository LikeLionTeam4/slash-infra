# 리소스 소유권 맵

"이 리소스는 어느 `environments/*` 디렉터리에서 apply하는가"를 한 그림으로 고정한 문서.
`docs/aws-architecture.md`의 §3(state)·§6(ECR)·§9-1(backend-cicd)·§11(환경 전략)에 흩어진
소유권 결정을 모았다 — 전부 "계정 공용 자원은 `bootstrap`, 환경별 자원은 그 환경 디렉터리"
원칙(§6)을 따르지만, 실제로 ECR을 `modules/eks`에서 `bootstrap`으로 옮긴 적이 있어서(§6)
그림으로 안 남기면 다시 헷갈리기 쉽다. 기준: 2026-08-19, 각 `environments/*/main.tf`의
`backend`/`terraform_remote_state`/모듈 호출 실제 코드.

```mermaid
flowchart TB
    subgraph BOOTSTRAP["environments/bootstrap\n계정당 최초 1회, state는 로컬(닭-달걀 문제, §3)"]
        STATE["S3: Terraform state 버킷\nslash-tfstate-&lt;account_id&gt;"]
        R53Z["Route53: sbsh.cloud zone"]
        ECR3["ECR: slash-api / slash-nlu / slash-llm"]
        CT["CloudTrail"]
        CICD["backend-cicd IAM Role ×3\n(GitHub OIDC → ECR push)"]
        BUDGET["AWS Budgets\n(Project=slash, 월 500)"]
    end

    subgraph LOCAL["environments/local\n개인 실험, apply↔destroy 반복"]
        L_EKS["eks\n(로컬 backend, 클러스터 검증 테스트베드로 계속 사용 중)"]
        L_REST["network / frontend / cognito\n/ database / observability\n2026-08-18 dev 상시운영 전환으로\ndestroy 후 dev에 흡수(§11-8)"]
    end

    subgraph DEV["environments/dev\nS3 backend, 상시 운영(2026-08-18~)"]
        D_NET["network"]
        D_COG["cognito"]
        D_DB["database"]
        D_EKS["eks"]
        D_LLM["llm-runtime"]
        D_OBS["observability"]
        D_FE["frontend"]
    end

    subgraph PROD["environments/prod\n미구축 — dev와 동일 모듈셋 예정"]
        P_ALL["착수 시 dev 패턴 그대로 복제"]
    end

    STATE -.->|"backend \"s3\" 로 참조"| DEV
    STATE -.->|"backend \"s3\" 로 참조(예정)"| PROD

    R53Z -.->|"zone_id 정적 값 복사\n(bootstrap state가 로컬이라 remote_state 불가)"| D_FE
    R53Z -.-> D_EKS
    R53Z -.-> D_COG
    ECR3 -.->|"image pull (sha- 태그, IMMUTABLE)"| D_EKS
    CICD -.->|"서비스 저장소 CI가 push"| ECR3

    D_NET -->|terraform_remote_state| D_DB
    D_NET -->|terraform_remote_state| D_EKS
    D_NET -->|terraform_remote_state| D_LLM
    D_DB -->|"terraform_remote_state\n(slash_api_secret_arns)"| D_EKS
    D_DB -->|"terraform_remote_state\n(rds_instance_id)"| D_OBS
```

## 왜 이렇게 나뉘었나

- **`bootstrap`이 소유하는 것들의 공통점**: "계정 하나에 한 번만 있어야 하는 자원"이다.
  ECR 리포지토리 이름이 겹치면 `local`/`dev`가 서로 충돌하고(§6), Route53 zone은 애초에
  계정에 1개, state 버킷은 그 자체가 다른 모든 환경의 backend이므로 먼저 있어야 한다(§3).
- **`bootstrap` 자신의 state는 로컬로 남아있다** — state 버킷을 만드는 그 순간엔 아직
  참조할 backend가 없는 최초 리소스라서다(§3). 이 때문에 `dev`/`prod`가 `bootstrap`의
  출력값을 `terraform_remote_state`로 끌어오지 못하고, `route53_zone_id`나 ECR
  리포지토리 URL 같은 값을 **정적으로 코드에 복사**해서 쓴다(`environments/dev/eks/domain.tf`
  의 주석이 이 이유를 명시). 즉 위 그림의 점선(bootstrap → dev)은 자동으로 갱신되는
  연결이 아니라 사람이 손으로 맞춰야 하는 연결이다 — bootstrap을 재apply해서 값이
  바뀌면 dev 쪽 정적 값도 같이 갱신해야 한다(실제로 §11 트러블슈팅에 "계정 재발급 후
  정적 zone ID가 옛 계정 값으로 남아있었다" 사례가 있음).
- **`local`은 지금 대부분 비어있다** — 처음엔 팀원이 각자 실험하는 환경으로 설계됐지만,
  실제로는 계정을 공유하기로 확정(§11)되면서 `network`/`frontend`/`cognito`가 `dev`
  상시운영 전환 시점에 역할이 완전히 겹쳐 destroy됐다. **`local/eks`만 예외**로 남아있다 —
  모듈 코드 자체를 실제 AWS에서 검증할 때 쓰는 apply→destroy 테스트베드 역할이라
  "상시 떠 있어야 하는 자원"이 아니라서 dev로 흡수될 이유가 없었다.
- **`dev` 내부의 화살표(`terraform_remote_state`)가 곧 apply 순서**다 — `network`가 먼저
  없으면 `database`/`eks`/`llm-runtime`이 서브넷·SG ID를 못 끌어오고, `database`가 먼저
  없으면 `eks`가 `slash-api`의 Secrets Manager ARN을 못 끌어와 IRSA Role 자체를 안 만든다
  (`modules/eks/slash_api_irsa.tf`의 `count = length(var.slash_api_secret_arns) > 0`).
  실제 적용 순서 기록은 `docs/operations-log.md` §5 참고.
- **`prod`는 아직 없다** — 착수 시 `dev`와 동일한 모듈 세트를 그대로 복제하는 게 설계
  의도(`docs/aws-architecture.md` §1, §11)라 이 그림의 `PROD` 박스는 지금은 빈 예정표다.

## 요약표

| 모듈 | 소유 디렉터리 | state backend | 핵심 의존성 |
| --- | --- | --- | --- |
| `ecr` | `bootstrap` | 로컬 | 없음 |
| Route53 zone | `bootstrap` | 로컬 | 없음 |
| `backend-cicd` ×3 | `bootstrap` | 로컬 | `ecr` (같은 root 내 참조) |
| CloudTrail / Budgets | `bootstrap` | 로컬 | 없음 |
| `network` | `dev` (local은 destroy됨) | S3 | 없음 |
| `cognito` | `dev` (local은 destroy됨) | S3 | 없음 (zone_id만 정적 참조) |
| `database` | `dev` (local은 미적용 상태였음) | S3 | `network` |
| `eks` | `dev` + `local`(테스트베드) | S3 / 로컬 | `network`, `database` |
| `llm-runtime` | `dev` | S3 | `network` |
| `observability` | `dev` (local은 미적용 상태였음) | S3 | `database` |
| `frontend` | `dev` (local은 destroy됨) | S3 | 없음 (zone_id만 정적 참조) |
| 전체 | `prod` | 미구축 | — |
