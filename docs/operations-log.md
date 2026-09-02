# 운영 로그 (Apply / Destroy 기록)

`docs/aws-architecture.md`가 "무엇을 왜 이렇게 설계했는가"를 다루는 설계 문서라면, 이 문서는 **실제로 AWS에 뭘 적용했고, 지우려면 뭘 해야 하는지**를 다루는 운영 기록이다. 인프라가 늘어날 때마다(RDS, EKS, dev/prod 환경 등) 계속 갱신되는 **살아있는 문서** — 아래 각 섹션을 그때그때 추가/수정한다.

> **주의**: 아래 리소스 ID·도메인은 특정 AWS 계정(`061039804626`, 2026-08-13 재발급 — 옛 계정 `727646470302`는 §4/§18 참고) 하나에서 실습한 결과다. 이 계정은 여러 수강생·팀이 공유하는 부트캠프 계정이라 `slash-` 접두사 없는 리소스가 섞여 보일 수 있다(`docs/resource-ownership.md` "계정 자체가 공유 강의용 계정" 절 참고). 다른 계정에서 시작한다면 이 값들은 안 맞고 처음부터 다시 apply해야 한다 — [README §다른 AWS 계정에서 시작하기](../README.md#다른-aws-계정에서-시작하기-팀원용) 참고.

## 1. 전체 순서 & 구현 상태 한눈에 보기

Apply는 이 표의 순서대로, **Destroy는 반대 순서**로 진행한다. "구현" 열이 ⬜(미구현)인 건 아직 모듈/코드 자체가 없다는 뜻 — 순서는 앞으로 만들 때를 대비한 계획이다.

| # | 환경 / 모듈 | 구현 | Apply 조건 (뭐가 있어야 되는지) | Destroy 시 주의사항 |
| --- | --- | --- | --- | --- |
| 1 | `environments/bootstrap` (state+DNS+**CloudTrail**) | ✅ 적용됨(state+DNS+CloudTrail 전체) — 2026-08-19 `terraform state`로 재확인, 별도 apply 이력 기록 없이 상시운영 전환(§11) 과정에서 함께 적용된 것으로 보임 | 없음 — 가장 먼저 | **가장 마지막에.** `prevent_destroy` 코드에서 제거해야 destroy 가능(§5-5). zone 지우면 `sbsh.cloud` DNS 전체가 끊김. CloudTrail 로그 버킷은 버저닝돼 있어 destroy 시 §4 "force_destroy 없는 버킷" 트러블슈팅 그대로 적용됨 |
| 2 | `environments/local/network` | ✅ 적용됨 | 없음 — 1번과 순서 무관, 독립적 | 4·5번(database/eks)**보다 나중에** 지워야 함(§5-3, §5-4) |
| 3 | `environments/local/frontend` (+ `modules/frontend-cicd` 배포 Role) | ✅ 적용됨 | 1번의 `hosted_zone_id` 필요 | **가장 먼저.** zone 안에 이 모듈이 만든 레코드가 있어서(§5-1) — `force_destroy=true`라 버킷 비우기는 불필요. CI Role은 이 환경 destroy 시 같이 지워짐(별도 조치 불필요) |
| 4 | RDS + Valkey + Secrets Manager | ✅ 코드 완료, **apply→검증→destroy 완료(현재는 미적용)** | 2번의 `private_db_subnet_ids`, `db_security_group_id` 필요 | 2번(network)**보다 먼저** 지워야 함(서브넷/SG 참조). local은 `deletion_protection=false`+`skip_final_snapshot=true`라 바로 destroy 가능 |
| 5 | EKS + EC2(3대) + ECR + ALB Controller Role | 클러스터/노드그룹/ALB Controller Role은 ✅ 코드 완료, **네 번째 apply→검증(로컬 배포 시나리오 5종, §7)→destroy까지 완료**(2026-08-12). **ECR만 계속 적용된 상태로 유지 중** | 2번의 `private_app_subnet_ids`, `eks_security_group_id` 필요. 4번과는 서로 독립적. ECR은 이 둘과 무관 — 클러스터 없이도 apply 가능 | 2번(network)**보다 먼저** 지워야 함(서브넷/SG를 참조 중). ECR도 `force_delete` 안 켜놔서 이미지 있으면 비우거나 옵션 추가 필요(§4 flow_logs 버킷과 같은 패턴) — 단 `mock-*` 태그는 lifecycle policy가 3일 후 자동 정리하므로 그 이미지들 때문에 막힐 일은 없음. **ALB Controller로 Ingress를 만든 적이 있다면 클러스터 destroy 전에 반드시 `kubectl delete ingress`부터 해야 함 — 단, ArgoCD `selfHeal`이 켜져 있다면 그 삭제가 즉시 재생성될 수 있으니 ArgoCD Application을 먼저 내리거나 정지시켜야 함**(§4 2026-08-12 항목 참고) |
| 6 | ALB Ingress + API용 ACM | ⬜ 미구현(도메인 연결 기준) — **로드밸런서 컨트롤러 자체는 IRSA Role apply + Helm 설치 + 실제 ALB 응답까지 검증 완료**(2026-08-11, ECR/EKS/ALB Controller 절 참고), 검증 후 destroy | 5번(로드밸런서 컨트롤러, 재현 방법 검증됨) + 1번(zone) 필요 | (미구현) |
| 9 | ArgoCD (GitOps 배포, `argocd/`) | ✅ 코드 완료(Helm 설치 절차 + Application manifest 3개), **apply→검증(Git 커밋→자동 배포 왕복)→destroy까지 완료**(2026-08-11, §3, [이슈 #10](https://github.com/LikeLionTeam4/slash-infra/issues/10)) | 5번(EKS 클러스터) 필요 | ArgoCD 자체는 AWS 리소스를 만들지 않아서(ALB Controller와 다름) `helm uninstall`만 하면 됨 — 클러스터 destroy 전 별도 K8s 정리 필수는 아니었음 |
| 7 | CloudWatch 알람(`modules/observability`) | ✅ 코드 완료, **apply→검증→destroy 완료(현재는 미적용)** (RDS CPU/스토리지만, ALB·GPU 알람은 6번·GPU 노드그룹 생기면 추가) | 4번의 `rds_instance_id` 필요 | 4번(database)**보다 먼저** 지워야 함(§5-2, 알람이 그 인스턴스ID를 참조) |
| 8 | Cognito(`modules/cognito`, User Pool+Client+Domain, Managed Login) | ✅ 적용됨, **상시 유지**(slash-web/slash-api가 이 User Pool ID·Client ID를 직접 참조하므로 database/eks처럼 검증 후 destroy하지 않는다) — 이메일+비밀번호만, Google 소셜 로그인은 채택 안 하기로 결정(2026-08-05) | 없음 — 1·2번과 무관, 완전히 독립적(VPC 안 씀) | 다른 모듈과 참조 관계 없어서 순서 무관이지만, slash-web/slash-api 로컬 설정이 이 값에 의존하므로 팀에 미리 알리지 않고 지우지 말 것 |

- **1·2·8번은 서로 의존이 없어서 순서를 바꾸거나 동시에 apply해도 무방**하다. 3번(frontend)부터는 1번이 먼저 끝나 있어야 하고, 4번(RDS+Valkey)·5번(EKS)은 둘 다 2번(network)의 서브넷·SG를 참조하므로 2번이 먼저 있어야 한다. 4번과 5번은 서로 무관 — 순서 상관없음. 7번(CloudWatch)은 4번 다음. 8번(Cognito)은 VPC를 쓰지 않는 리전 서비스라 다른 모든 모듈과 무관.
- **Destroy는 표 번호의 역순이 기본**이지만, 4·5번은 2번을, 7번은 4번을 참조하고 있어서 각각 **참조 대상보다 반드시 먼저** 지워야 한다.
- dev/prod 환경 자체는 아직 미구축 — 계정 구조는 `docs/aws-architecture.md` §11 참고 (local은 팀원마다 다른 계정, prod는 담당자 2명이 계정 하나 공유).

## 2. 현재 적용 상태

| 환경 | 리소스 수 | 핵심 output | 상태 |
| --- | --- | --- | --- |
| `environments/bootstrap` | 36 | `route53_zone_id = Z02458772F0ED1QG30X6D`, `bucket_name = slash-tfstate-061039804626`, `ecr_repository_urls = {slash-api, slash-nlu, slash-llm}`, `backend_cicd_role_arns = {api, nlu, llm}`, `cloudtrail_arn = arn:aws:cloudtrail:ap-northeast-2:061039804626:trail/slash-trail`, `cloudtrail_bucket_name = slash-cloudtrail-061039804626` | 적용됨(새 계정, §3 2026-08-13 계정 재발급 항목 참고). ECR 3+lifecycle policy 3을 `local/eks`에서 이전(2026-08-12, §6), 백엔드 CI용 IAM Role 3개(`modules/backend-cicd`). **CloudTrail도 적용된 상태**(2026-08-19 확인, §1 참고) — 단일 리전 트레일, S3에만 적재 중이고 CloudWatch Logs/Athena/GuardDuty 등 분석 연동은 아직 없음 |
| `environments/local/network` | 0 | – | **미적용(2026-08-18 destroy, §11-8)** — dev가 상시운영으로 전환되며 local의 module-검증 목적이 dev로 흡수됨. flow-log 버킷에 버전 3301개 쌓여있어 `delete-objects`로 먼저 비운 뒤 destroy |
| `environments/local/frontend` | 0 | – | **미적용(2026-08-18 destroy)** — dev.sbsh.cloud가 생기면서 역할 완전히 흡수(§11-7) |
| `environments/local/cognito` | 0 | – | **미적용(2026-08-18 destroy)** — dev Cognito(`ap-northeast-2_kiW46VZ9O`)로 흡수 |
| `environments/local/eks` | 0 | – | 미적용 — ECR도 bootstrap으로 이전돼서 이제 아무것도 안 남음. 클러스터 재현 이력은 §3/§7 참고 |
| `environments/dev/network` | 0 | – | **미적용(2026-09-03 destroy, §39)** — dev 전체 destroy. flow-log 버킷에 버전 9,738개 쌓여있어 배치로 비운 뒤 destroy |
| `environments/dev/cognito` | 0 | – | **미적용(2026-09-03 destroy, §39)** |
| `environments/dev/database` | 0 | – | **미적용(2026-09-03 destroy, §39)** |
| `environments/dev/eks` | 0 | – | **미적용(2026-09-03 destroy, §39)** |
| `environments/dev/observability` | 0 | – | **미적용(2026-09-03 destroy, §39)** |
| `environments/dev/llm-runtime` | 0 | – | **미적용(2026-08-25 destroy, §23)** — 표기 누락 정정. 코드는 보존, 필요 시 재apply로 복원 가능 |
| `environments/dev/frontend` | 0 | – | **미적용(2026-09-03 destroy, §39)** |
| `environments/prod/*` | – | – | 미구축 |

계정은 `061039804626`(부트캠프 공유, 2026-08-13 재발급 — 옛 계정 `727646470302`는 더 이상 접근 불가). 리전 `ap-northeast-2`. 이 표는 스냅샷이라 실제 값이 궁금하면 각 디렉터리에서 `terraform output`으로 재확인할 것 — 아래는 마지막 갱신 시점(2026-08-13) 기준.

## 3. Apply 이력

| 날짜 | 환경 | 내용 | 비고 |
| --- | --- | --- | --- |
| 2026-08-04 | `bootstrap` | state 버킷 + `sbsh.cloud` Route53 zone 생성 | 가비아 네임서버를 output의 `route53_name_servers` 4개로 변경, 전파 확인 후 진행 |
| 2026-08-04 | `local/frontend` | S3+CloudFront+ACM+DNS 10개 생성 → `slash-web` 빌드 후 `aws s3 sync`로 콘텐츠 배포 | 첫 apply, 문제 없이 한 번에 완료 |
| 2026-08-04 | `local/network` | VPC 등 38개 생성 시도 | **1차 실패** — §4 참고. 코드 수정 후 나머지 7개 재적용해서 완료 |
| 2026-08-04 | `local/eks` | 코드 작성 + `plan` 검증(20개 리소스) | **아직 apply 안 함** — EKS 컨트롤플레인이 월 ~$75로 지금까지 중 가장 비싸서 별도 확인 후 진행 예정 |
| 2026-08-04 | `local/database` | 코드 작성 + `plan` 검증(7개 리소스) | **아직 apply 안 함**. `aws_elasticache_cluster`는 `auth_token` 미지원이라 `aws_elasticache_replication_group`(노드 1개)으로 교체 — §4 참고 |
| 2026-08-04 | `bootstrap` | CloudTrail 관련 코드 작성 + `plan` 검증(7개 리소스 추가) | **아직 apply 안 함**. 기존 state 버킷/zone(5개)엔 변경 없음 |
| 2026-08-04 | `local/observability` | 코드 작성 + `plan` 검증(3개 리소스: SNS 토픽 + RDS 알람 2개) | **아직 apply 안 함** |
| 2026-08-04 | `local/frontend` | `force_destroy = true`로 변경 적용 | AWS API 호출 없는 순수 Terraform state 변경 (§5-1 참고) |
| 2026-08-04 | `local/frontend` | 버킷명에 계정ID 자동 접미사 적용 (`slash-web-local` → `slash-web-local-727646470302`) | S3 버킷명 전역 유일성 때문에 버킷 교체(destroy+재생성) 발생 — 재적용 후 `aws s3 sync` + CloudFront invalidation으로 콘텐츠 복구, 팀원 신규 apply는 처음부터 이 이름으로 생성되어 영향 없음 |
| 2026-08-04 | `bootstrap` | CloudTrail 7개 리소스(trail + 로그 버킷) apply → state로 적용 확인 → 즉시 destroy | 지금 당장은 CloudTrail 로그를 분석할 일이 없어서 코드/plan 검증 목적으로만 apply했고, 확인 후 바로 정리. `route53_zone`·`tfstate` 버킷은 같은 디렉터리에 있지만 건드리면 안 돼서 전체 destroy 대신 `-target`으로 CloudTrail 리소스 6개만 지정해 destroy — 트레일이 짧은 순간에도 로그 파일 1개를 이미 써놔서 버킷이 안 비어 1차 실패(§4 참고), 버전까지 수동으로 지운 뒤 버킷만 재destroy로 완료. §1 표는 "코드 완료, 미적용" 상태 그대로 유지 |
| 2026-08-04 | `local/database` | RDS(`db.t4g.small`) + Valkey(`cache.t4g.micro`) 등 7개 apply | 문제 없이 한 번에 완료. `rds_endpoint`, `valkey_endpoint` 등 output 확인 |
| 2026-08-04 | `modules/database` | `outputs.tf`의 `rds_instance_id`를 `aws_db_instance.main.id` → `.identifier`로 수정, database 환경 재apply(0 added/changed — output만 갱신) | observability를 붙이기 직전에 발견 — §4 "rds_instance_id가 DbiResourceId를 가리킴" 참고 |
| 2026-08-04 | `local/observability` | SNS 토픽 + RDS 알람(CPU/스토리지) 3개 apply | `slash-rds-cpu-local` 알람이 실제 RDS CPU 데이터(5~20%)를 정상 수신하며 `OK` 상태인 것까지 확인 — 위 output 수정이 유효했음을 검증 |
| 2026-08-04 | `local/eks` | 클러스터·OIDC·Karpenter IAM 역할까지는 성공, `aws_eks_node_group.general` 생성 **1차 실패** | §4 "launch template에 iam_instance_profile 지정 불가" 참고. `modules/eks/node_group.tf` 수정 후 재apply로 노드그룹까지 20개 전부 완료, 노드그룹 `ACTIVE`(desired 3) 확인 |
| 2026-08-04 | `local/eks` → `local/observability` → `local/database` | 확인 끝난 뒤 오늘 apply 역순으로 destroy (EKS 20개 → observability 3개 → database 7개) | 셋 다 `terraform state list` 결과 0개로 정상 정리. network(40개)·bootstrap(5개+data source)은 그대로 |
| 2026-08-05 | `local/eks` | 재apply(20개) — 버그 수정 후 1차 시도부터 문제없이 완료 | 어제 §4의 launch template 수정이 유효함을 재확인 |
| 2026-08-05 | `local/eks` (`irsa_test.tf`, 임시) | IRSA 배선 자체를 검증하기 위해 테스트용 IAM Role + Secrets Manager 시크릿 4개를 임시로 apply → K8s ServiceAccount(`eks.amazonaws.com/role-arn` 어노테이션) + 테스트 파드로 실제 `sts:AssumeRoleWithWebIdentity` + `secretsmanager:GetSecretValue` 성공 확인 → 검증 후 K8s 리소스·Terraform 리소스·`irsa_test.tf` 파일까지 전부 삭제 | RDS/Valkey는 다시 안 띄우고 더미 시크릿으로만 검증(비용·시간 절약) — `slash-api`가 실제로 쓸 경로와 메커니즘은 동일. `AWS_ROLE_ARN`/`AWS_WEB_IDENTITY_TOKEN_FILE` 자동 주입, `assumed-role/slash-irsa-test-local/...`로 정확히 assume되는 것까지 확인 — 문제 없음 |
| 2026-08-05 | `local/eks` | 위 검증 끝난 뒤 destroy(EKS 20개 + IRSA 테스트 4개 = 24개) | `terraform state list` 0개로 정상 정리 |
| 2026-08-05 | `modules/frontend-hosting` | `bucket_arn`, `cloudfront_distribution_arn` output 2개 추가 | 순수 추가라 기존 리소스(S3/CloudFront, 지금 `local.sbsh.cloud`로 실서빙 중)엔 영향 없음 — `local/frontend` plan에서 `0 to change` 확인 |
| 2026-08-05 | `modules/frontend-cicd` (신규) + `local/frontend` | GitHub OIDC 배포 Role 2개 apply(`aws_iam_role`, `aws_iam_role_policy`) | 계정에 이미 있는 GitHub OIDC provider(다른 팀 `Team1` 소유)를 `data` 소스로 참조만 하고 직접 만들지 않음 — §4 참고. trust policy가 `repo:LikeLionTeam4/slash-web:ref:refs/heads/main`으로 정확히 제한된 것, 백엔드 ECR 권한은 없고 S3/CloudFront 권한만 붙은 것까지 `aws iam get-role`로 확인 |
| 2026-08-05 | `slash-web`(별도 저장소) | `.github/workflows/deploy-local.yml` 추가, main 기준 새 브랜치(`ci/deploy-local-workflow`)로 PR #14 오픈 → 리뷰 승인 후 merge | `dev`가 `main`보다 49개 커밋 앞서 있어서, `dev`를 그대로 merge하면 CI 테스트가 아니라 사실상 첫 프로덕션 릴리스가 될 뻔함 — `main` 기준 브랜치로 워크플로 파일만 분리해서 올림 |
| 2026-08-05 | `slash-web` | PR #14 merge 직후 워크플로 실행 → `npm ci` 단계에서 실패 | `main`이 `README.md`뿐인 빈 스텁 브랜치였음 — §4 참고 |
| 2026-08-05 | `modules/frontend-cicd` + `local/frontend` | `github_branch`를 `main`→`dev`로 재apply(trust policy `sub` 조건 1개만 변경) | dev로 임시 전환, TODO로 "dev->main 릴리스 시 되돌릴 것" 남김 — §4 참고 |
| 2026-08-05 | `slash-web` | dev 기준 새 브랜치(`ci/deploy-dev-workflow`)로 PR #15 오픈 → merge → 워크플로 실행 → `sts:AssumeRoleWithWebIdentity` `AccessDenied`로 **2차 실패** | GitHub OIDC "immutable IDs"로 `sub` 클레임에 조직/저장소 뒤 숫자 ID가 붙어 나와서 `StringEquals` 조건과 불일치 — §4 참고 |
| 2026-08-05 | `modules/frontend-cicd` + `local/frontend` | trust policy 조건을 `StringEquals`→`StringLike`+와일드카드로 재apply | §4 참고 |
| 2026-08-05 | `slash-web` | `workflow_dispatch`로 재실행 → **전체 스텝 성공**, `local.sbsh.cloud`의 `index.html` 실제 갱신 확인(`last-modified` 헤더로 검증) | CI/CD 파이프라인 end-to-end 검증 완료 |
| 2026-08-05 | `modules/cognito`(신규) + `local/cognito` | User Pool + 퍼블릭 App Client + Domain apply 시도 → `sign_in_policy.allowed_first_auth_factors = ["EMAIL_OTP"]`만으로 **1차 실패** | Cognito API가 `PASSWORD`를 필수 포함하도록 요구 — §4 참고 |
| 2026-08-05 | `modules/cognito` + `local/cognito` | `allowed_first_auth_factors`에 `PASSWORD` 추가 후 재apply(3개) → 성공 | `user_pool_id = ap-northeast-2_s2ZnfGrqo` — 최초에는 SPA가 Cognito API를 직접 호출(SDK 방식)하는 걸로 설계했었음(이후 아래 항목에서 뒤집힘) |
| 2026-08-05 | `modules/cognito` + `local/cognito` | `slash-web`팀이 받은 `frontend-api-contract.md`(백엔드) 확인 결과 인증 방식이 Authorization Code+PKCE(Managed Login 리다이렉트) 전제라는 걸 확인 → App Client의 OAuth 설정을 `enable_google_idp` 조건부에서 상시 활성화로 변경, `refresh_token_validity`를 30일→7일(계약서 권장값)로 조정, `callback_urls`에 `/callback` 경로 추가하여 재apply | 이전에 만들었던 SDK 직접 호출 방식(`slash-web`의 `cognitoAuth.ts`)은 전량 폐기 — `oidc-client-ts` 기반으로 재작성 |
| 2026-08-05 | `local/cognito` (`aws_cognito_user_pool_domain.main`) | `managed_login_version`을 명시 안 해서 기본값(1, classic Hosted UI)으로 생성돼 있던 걸 2(Managed Login)로 재apply | 브랜딩 커스터마이징(다음 항목)이 v2에만 적용되는데 실제 도메인은 v1이었던 걸 뒤늦게 발견 — §4 참고할 만한 함정이지만 별도 트러블슈팅 절은 안 만듦(원인이 단순 누락) |
| 2026-08-05 | Cognito Managed Login 브랜딩 | `aws cognito-idp create/update-managed-login-branding` **CLI로** slash-web의 DESIGN.md 토큰(canvas/surface/hairline/foreground/muted, 다크·라이트 `DYNAMIC` 전환, radius 스케일)에 맞춰 커스터마이징 + `public/logo.png`를 FORM_LOGO 에셋으로 업로드 | **Terraform이 아니라 AWS CLI로 관리** — AWS provider가 `~> 5.0`(설치된 5.100.0)까지만 허용되는데 `aws_cognito_managed_login_branding` 리소스는 6.x부터 지원돼서 당장은 Terraform으로 못 옮김. 프로바이더를 6.x로 올리는 건 EKS/RDS 등 다른 모든 모듈에 영향을 주는 큰 변경이라 이번 작업 범위로는 보류 — 나중에 6.x로 올릴 계획이 서면 이 브랜딩도 그때 같이 Terraform으로 옮길 것. 로고 이미지 자체는 에셋 등록까지 됐는데 실제 렌더링이 안 되는 원인 미해결로 남음(placeholder 아이콘만 보임) |
| 2026-08-05 | `modules/cognito` + `local/cognito` | Google 소셜 로그인을 최종적으로 채택하지 않기로 결정 → `enable_google_idp`/`google_client_id`/`google_client_secret` 변수와 `google_idp.tf`(`aws_cognito_identity_provider.google`) 삭제, `terraform.tfvars.example` 삭제 | plan 결과 `No changes`(애초에 Google IdP를 apply한 적이 없어서 실제 리소스는 그대로) — 코드만 정리됨. `slash-web` 로그인 화면의 "Google로 계속하기" 버튼은 UI에는 남기되 비활성 상태 유지(팀 결정) |
| 2026-08-11 | `modules/eks/ecr.tf` | lifecycle policy에 `mock-` 접두어 태그 전용 규칙(3번, 3일 후 자동 정리) 추가 | `slash-api`/`slash-nlu`/`slash-llm` 저장소에 아직 Dockerfile/CI가 없어서, 클러스터 없이 ECR push 파이프라인만 먼저 검증하기로 함 — 기존 `sha-` 태그 규칙(개수 기준)은 mock 이미지에 적용 안 돼서 방치될 수 있었음. 공유 계정에 정리 안 된 이미지가 안 남게 별도 규칙으로 처리 |
| 2026-08-11 | `local/eks` (`-target`으로 ECR만) | `aws_ecr_repository.services` 3개 + `aws_ecr_lifecycle_policy.services` 3개 apply(6개) → 성공 | 클러스터/노드그룹은 제외하고 ECR만 먼저 apply(비용 거의 0). 다른 팀 리포지토리(`my-ecr-nyj`, `my-ecr-mjh`, `team1-truss`, `team5/ecr/qket`)와 이름 충돌 없음을 사전 확인 |
| 2026-08-11 | `mock-services/`(신규, `slash-infra` 저장소 내) | `slash-api`/`slash-nlu`/`slash-llm` 각 실제 포트(8080/8001/8000)를 흉내낸 최소 Python HTTP 서버(`/health` 200 JSON) 3개 작성, 로컬 빌드·실행 검증(Colima) 후 `mock-20260811` 태그로 ECR push까지 성공 | 실제 서비스 저장소에 Dockerfile이 생기기 전까지 ECR/EKS 배포 파이프라인 배선을 확인하기 위한 임시 placeholder — 실제 Dockerfile/CI가 생기면 이 디렉터리는 삭제 예정. **이번에 apply한 ECR도 검증 목적의 테스트 자원이라, 작업이 모두 끝나면 destroy 여부를 다시 논의하기로 함** |
| 2026-08-11 | `local/eks` (나머지 14개: 클러스터+OIDC+노드그룹) | ECR 이후 나머지 리소스까지 apply(20개 전부), 클러스터·노드그룹 `ACTIVE` 확인 | 오늘 안에 끝내는 것을 전제로 apply — 실제 서비스 Dockerfile이 아직 없어서 계속 켜둘 이유가 없고, 검증 끝나면 바로 destroy할 예정(§1) |
| 2026-08-11 | `mock-services/` 이미지 재빌드 | `mock-20260811`(arm64)로 배포한 파드가 `exec format error`로 크래시 → `mock-20260811-amd64` 태그로 amd64 재빌드 후 재배포, 3개 서비스 전부 `Running` + `/health` 정상 응답까지 확인 | §4 "로컬(Apple Silicon) 빌드 이미지와 EKS 노드 아키텍처 불일치" 참고. 두 태그 다 `mock` 접두어라 lifecycle policy가 3일 후 둘 다 자동 정리(별도 조치 불필요) |
| 2026-08-11 | `modules/eks/alb_controller.tf`(신규) + `local/eks` | ALB Controller용 IRSA Role apply(2개) — 정책 문서는 AWS 공식 배포본(`kubernetes-sigs/aws-load-balancer-controller`)을 그대로 파일로 받아 `file()`로 참조 | 손으로 옮기면 86개 action 중 일부를 누락할 위험이 있어 원본 그대로 커밋 |
| 2026-08-11 | AWS Load Balancer Controller (Helm, `kube-system`) | `eks/aws-load-balancer-controller` 차트 설치 → 컨트롤러 2/2 Running. 테스트 Ingress(internet-facing)로 실제 ALB 프로비저닝 → 타겟 healthy → `/health` 응답까지 전 구간 확인 | ALB Controller가 `alb`라는 `IngressClass`를 자동 생성해줌 — 이후 `kubernetes.io/ingress.class` 어노테이션 대신 `spec.ingressClassName: alb` 사용(§4 "deprecated ingress.class" 참고) |
| 2026-08-11 | `helm/`(신규) | `slash-api`/`slash-nlu`/`slash-llm` 3개 Helm chart 작성(서비스별 디렉터리 + `values-{local,dev,prod}.yaml`, §9 구조). `helm lint` 통과 + `helm template \| kubectl apply --dry-run=server`로 API 서버 스키마 검증까지 통과 | `values-local.yaml`은 `mock-20260811-amd64` 이미지를 기본값으로 사용. `image.repository`(ECR URL, 계정ID 포함)는 정적 값 — Terraform output에서 자동 동기화 안 됨, 계정 구조 바뀌면(§13 TODO) 수동 갱신 필요 |
| 2026-08-11 | `local/eks` destroy (ECR 제외) | `kubectl delete ingress`로 ALB부터 먼저 정리(§4 "ALB 고아 자원" 참고) → 확인 후 클러스터+노드그룹+ALB Controller/Karpenter Role 등 16개를 `-target`으로 지정해 destroy, ECR 6개는 유지 | 이 Terraform 버전(1.15.8)엔 `-exclude` 플래그가 없어서(§4 참고) `terraform state list`로 뽑은 목록에서 ECR만 걸러 `-target`을 16개 나열하는 방식으로 처리 |
| 2026-08-11 | `local/eks` (전체 재apply, [이슈 #10](https://github.com/LikeLionTeam4/slash-infra/issues/10)) | 클러스터+노드그룹+ALB Controller/Karpenter Role 등 16개 재apply(§1 표 5번 세 번째 라운드) → 3개 노드 전부 `Ready`, amd64 확인 | 1차 시도가 `Failed to load plugin schemas: timeout while waiting for plugin to start` 에러로 실패 — provider 스키마 로딩 타임아웃(일시적), state 변경 없이 그대로 재시도해서 성공. 첫 apply 명령을 `cd environments/local/eks && terraform apply`로 실행했는데 이미 그 디렉터리에 있어서 `cd`가 실패한 채로 백그라운드에 올라갔던 것도 원인 중 하나 — 백그라운드로 넘길 때는 항상 `pwd`로 현재 디렉터리를 먼저 확인할 것 |
| 2026-08-11 | ArgoCD (Helm, `argocd` 네임스페이스) + `argocd/`(신규, [이슈 #10](https://github.com/LikeLionTeam4/slash-infra/issues/10)) | 공식 `argo-cd` Helm chart(v7.7.11) 설치 → 전 파드 Running. `argocd/applications/{slash-api,slash-nlu,slash-llm}.yaml` 작성(각각 `helm/<service>` 경로 + `dev` 브랜치 + `values-local.yaml`, `syncPolicy.automated` 켬) → 커밋 후 `dev`에 push, `kubectl apply`로 3개 Application 등록 → 전부 `Synced`, mock 파드 3개 `Running`까지 확인 | ALB Controller는 이번 라운드엔 재설치하지 않아서 `slash-api`의 Ingress는 `Progressing` 상태로 남음(주소 미할당) — 이슈 #10 범위(GitOps 배선 검증)엔 지장 없음, ALB 자체는 §1 6번에서 이미 별도 검증됨. 저장소가 public이라 ArgoCD에 별도 git credential 등록 불필요했음 |
| 2026-08-11 | GitOps 자동 배포 실제 검증([이슈 #10](https://github.com/LikeLionTeam4/slash-infra/issues/10)) | `helm/slash-api/values-local.yaml`의 `replicaCount`를 1→2로 바꿔 커밋+push만 하고 수동 `kubectl`/`helm` 명령 없이 대기 → **약 3분 48초 뒤 ArgoCD가 자동으로 감지해 sync, 파드 2개로 자동 확장**됨을 확인. 이어서 1로 되돌리는 커밋도 push해서 반대 방향(자동 축소)까지 왕복 검증 — 약 6분 뒤 자동 반영, "Git 커밋 → 배포"가 실제로 무인 자동화되는 것을 최종 확인 | ArgoCD 기본 재동기화 주기(`timeout.reconciliation`, 기본 180초)가 앱마다 정확히 3분 간격은 아니고 앱 컨트롤러 큐 상황에 따라 3~6분 정도 편차가 있었음 — "커밋 후 몇 분 안에 반영되는지"를 딱 잘라 약속하기보다 "수 분 내 자동 반영"으로 이해하는 게 맞음. 검증용 `bash until` 폴링 스크립트에 macOS 기본 환경엔 없는 `timeout` 커맨드를 썼다가 즉시 실패했던 것도 발견 — 이 환경에서 폴링 타임아웃이 필요하면 `SECONDS` 내장변수로 직접 구현할 것 |
| 2026-08-11 | ArgoCD + `local/eks` destroy(ECR 제외, [이슈 #10](https://github.com/LikeLionTeam4/slash-infra/issues/10) 검증 종료) | `helm uninstall argocd -n argocd` → `kubectl delete namespace argocd` → `aws elbv2 describe-load-balancers`로 `slash-*` ALB가 없는 것 확인(이번 라운드는 ALB Controller 자체를 안 띄웠으므로 예상대로 없음) → 클러스터+노드그룹+Role 등 16개를 `-target`으로 destroy | ArgoCD는 AWS 리소스를 직접 만들지 않아서 ALB Controller 때와 달리 `kubectl delete ingress` 같은 사전 정리가 필수는 아니었음. destroy 후 `terraform plan`으로 "16 to add, 0 to destroy"만 나오는 것까지 확인해 state가 깨끗하게 ECR 6개만 남았음을 재확인 |
| 2026-08-12 | `local/eks` (네 번째 재apply, §7 로컬 배포 시나리오 검증용) | 클러스터+노드그룹+ALB Controller/Karpenter Role 등 16개 apply → 3개 노드 전부 `Ready`, amd64 확인. `aws eks update-kubeconfig`로 kubeconfig 갱신 | 지난 세 번의 apply와 동일하게 1차 시도부터 문제없이 완료(1분 49초) — §4 launch template/스키마 타임아웃 이슈는 재현 안 됨 |
| 2026-08-12 | ArgoCD + AWS Load Balancer Controller 재설치(§7 시나리오 3용) | `helm install argocd`(argocd 네임스페이스) → 3개 Application 재등록 → `aws-load-balancer-controller` IRSA ServiceAccount 수동 생성 + Helm 설치(2/2 Running) | 클러스터를 destroy→재apply하면 ArgoCD/ALB Controller도 함께 사라지므로, 재apply 때마다 `argocd/README.md`·§3 2026-08-11 절차를 그대로 반복 실행해야 한다는 걸 재확인 |
| 2026-08-12 | §7 로컬 배포 시나리오 5종 검증 종료 후 `local/eks` destroy(ECR 제외) | `kubectl delete ingress slash-api` → **ArgoCD selfHeal이 즉시 재생성**(§4 참고, 예상 못 한 부수효과) → `helm uninstall argocd`/`aws-load-balancer-controller` → `terraform destroy -target`으로 16개 정리 → orphan ALB 1개 + 연관 target group·보안그룹 2개를 AWS CLI로 수동 정리(§4) → `terraform plan`으로 "16 to add, 0 to destroy" 재확인, 다른 팀 리소스와 섞이지 않는 것까지 전체 스윕으로 확인 | ECR 6개만 남기고 정상 정리 완료 |
| 2026-08-12 | `slash-api`/`slash-nlu`/`slash-llm` GitHub 저장소 설정 (§9-3, [이슈 #17](https://github.com/LikeLionTeam4/slash-infra/issues/17)) | 세 저장소 `main` 브랜치에 `required_linear_history=true`(+`allow_force_pushes`/`allow_deletions` 비활성) 브랜치 보호 규칙 적용 — `gh api --method PUT .../branches/main/protection`. `production` Environment 생성은 API 호출이 자동 모드 분류기에 두 번 차단되어 사용자가 웹 UI로 직접 진행, `infra-team-4` 팀을 필수 리뷰어로 지정 완료(개인이 아닌 팀 전체라 한 사람 부재 시에도 승인 가능) — 3개 저장소 전부 API로 재확인함 | Terraform 관리 대상이 아닌 GitHub 저장소 설정이라 이 문서(§9-3)와 이슈로만 추적. 세 저장소 다 `main`이 `dev`보다 9~35개 커밋 뒤처진 미사용 브랜치라 팀 작업에 즉시 영향 없음 확인 후 적용 |
| 2026-08-12 | ECR을 `local/eks`에서 `bootstrap`으로 이전(§6, dev 착수 전 정리) | `modules/ecr`(신규) 작성 → `environments/bootstrap`에서 `terraform import`로 기존 6개 리소스(리포지토리 3 + lifecycle policy 3) 흡수 → `terraform apply -target=module.ecr`로 태그만 갱신(`Environment: local→shared`, `Service: eks→ecr`) → `local/eks`에서 `terraform state rm`으로 6개 제거, `modules/eks/ecr.tf` 삭제 → 양쪽 `terraform plan`으로 "0 to destroy" 확인(local/eks는 클러스터 재apply분 16개만 남음, ECR 관련 변경 없음), `terraform validate` 통과 | 실제 AWS 리소스는 한 번도 안 건드림(`state rm`/`import`만 사용) — `dev/eks`를 새로 만들 때 같은 이름의 ECR을 또 만들려다 충돌하는 걸 미리 막기 위한 작업. 계정 공유 결정(§11)도 이 김에 문서에 반영 — local도 처음부터 팀 전체가 계정 하나(`727646470302`)를 공유해온 것으로 확인, 문서상 "팀원마다 다른 계정" 문구를 정정 |
| 2026-08-12 | `dev/network` (§8 dev 착수 1단계, 1차) | VPC(10.1.0.0/16) 등 40개 apply — `modules/network` 재사용, `nat_gateway_per_az` 오버라이드 없이 모듈 기본값(AZ당 1개, local만 예외로 1개로 깎아둔 것) 그대로 사용해 NAT 2개 생성. **처음부터 `backend "s3"`**(`slash-tfstate-727646470302`, key `dev/network.tfstate`, `use_lockfile=true`)로 시작 — local처럼 나중에 옮기지 않음 | `aws ec2 describe-vpcs`/`describe-nat-gateways`로 CIDR·NAT 2개 `available` 상태 확인 |
| 2026-08-12 | `dev/network` CIDR 변경(10.1.0.0/16 → 10.8.0.0/16) 후 재apply | 환경별로 간격을 둔 CIDR 체계로 정리(local=10.0.0.0/16, dev=10.8.0.0/16, prod=10.16.0.0/16 예정) — VPC CIDR은 생성 후 못 바꿔서(`ForceNew`) destroy 후 재apply. destroy 중 `slash-vpc-flow-logs-dev-727646470302` 버킷만 버저닝 때문에 1차 실패(§4 "versioning 켜진 S3 버킷" 항목과 동일 패턴) → 그 버킷 안의 객체 버전 7개(전부 방금 그 VPC가 만든 flow log, 다른 리소스와 무관 확인 후) 수동 삭제 → 재destroy로 완료 → 새 CIDR로 재apply, `aws ec2 describe-vpcs`로 `10.8.0.0/16` 확인 | dev-architecture.drawio의 CIDR 표기도 같이 갱신(10.1→10.8). §5 destroy 순서상 database/eks가 여기 서브넷을 참조하므로 dev 착수 기간 내내 destroy하지 않고 유지(local의 network과 동일한 취급) |
| 2026-08-12 | `dev/cognito` (§8 dev 착수 2단계) | `modules/cognito` 재사용, User Pool `slash-users-dev` 등 3개 apply. local Cognito와 완전히 별도 리소스(같은 계정을 공유해도 Cognito는 ECR과 달리 이름 충돌 제약이 없어 환경별로 만드는 게 자연스러움) | `aws cognito-idp describe-user-pool`로 `slash-users-dev` 생성 확인. local Cognito는 이번 작업과 무관하게 그대로 유지(사용자 요청 — "정리하자고 하기 전까지 정리 안 하면 됨") |
| 2026-08-12 | `dev/database` (§8 dev 착수 3단계) | `modules/database` 재사용, RDS(Multi-AZ) + Valkey + Secrets Manager 시크릿 2개 등 7개 apply. `dev/network` 서브넷/보안그룹은 `terraform.tfvars` 수동 복사 대신 `terraform_remote_state`로 직접 참조(dev부터는 S3 backend라 가능 — local의 수동 tfvars 방식과 다름). `rds_deletion_protection=false`/`rds_skip_final_snapshot=true`로 임시 오버라이드 — 이번 apply→검증→destroy 사이클 편의용, `rds_multi_az`는 오버라이드 없이 모듈 기본값(true) 사용. RDS 생성에 12분 51초 소요(Multi-AZ라 local의 단일 AZ보다 오래 걸림) | `aws rds describe-db-instances`로 `MultiAZ: true`/`available`, `aws elasticache describe-replication-groups`로 Valkey `available` 확인 |
| 2026-08-12 | `dev/eks` (§8 dev 착수 4단계) | `modules/eks` 재사용, `dev/network` 참조도 `terraform_remote_state`로. ECR은 이제 이 모듈에 없어서(2026-08-12 이전, §6) local과 이름 충돌 없이 16개 1차 시도부터 정상 apply(1분 49초) | `aws eks update-kubeconfig` 후 `kubectl get nodes`로 3개 노드 전부 `Ready`, `10.8.x.x`(dev VPC) amd64 확인 |
| 2026-08-12 | `dev/observability` (§8 dev 착수 5단계) | `modules/observability` 재사용, `dev/database` 참조도 `terraform_remote_state`로. RDS CPU/스토리지 알람 2개 + SNS 토픽(`alarm_email` 미설정, 구독 없이 토픽만) 등 3개 apply | `aws cloudwatch describe-alarms`로 처음엔 `INSUFFICIENT_DATA` → 72초 뒤 `slash-rds-cpu-dev`가 `OK`로 전환, 실제 CPU 데이터 수신 확인(local의 2026-08-04 검증과 동일 패턴) |
| 2026-08-12 | ArgoCD + dev Application 매니페스트(§8 6단계) | `slash-eks-dev`에 ArgoCD Helm 설치 → `argocd/applications-dev/`(신규, `values-local.yaml` 대신 `values-dev.yaml` 참조) 3개 `kubectl apply` | `slash-api`/`slash-nlu`/`slash-llm` 전부 `Synced` — Helm chart 렌더링·적용 자체는 정상 작동 확인. 파드는 `InvalidImageName`(예상된 상태, `image.tag`가 아직 빈 값 — 이슈 #11 대기). **의도적으로 여기서 멈춤**: 실제 이미지가 없는 채로 mock 이미지를 다시 붙여 검증할지 물었더니 "Dockerfile 만들어지면 테스트하도록 하면 될 거 같아"로 결정 — local에서 이미 5개 시나리오로 메커니즘 자체는 충분히 검증했다고 판단, 반복 검증 생략 |
| 2026-08-12 | AWS Load Balancer Controller + ACM 인증서(§8 6단계) | `slash-eks-dev`에 ALB Controller IRSA ServiceAccount + Helm 설치(2/2 Running). `environments/dev/eks/domain.tf`(신규)로 `api.dev.sbsh.cloud` ACM 인증서 + Route53 DNS 검증 레코드 + 검증 완료까지 3개 apply — bootstrap의 `route53_zone_id`는 bootstrap state가 로컬 전용이라(§3 닭-달걀 문제) `terraform_remote_state`로 못 끌어와서 ECR URL과 같은 이유로 정적 값(`Z03858108FMADVU36PUA`)으로 직접 넣음. `helm/slash-api/values-dev.yaml`에 인증서 ARN을 `alb.ingress.kubernetes.io/certificate-arn` 어노테이션으로 미리 반영 | `aws acm describe-certificate`로 `Status: ISSUED` 확인. **Route53 A레코드(ALB 실제 연결)는 의도적으로 미룸** — 지금은 검증할 앱이 없어서(위 항목), 실제 Dockerfile 준비되고 앱이 안정적으로 뜬 뒤에 마저 연결하기로 함 |
| 2026-08-12 | 백엔드 CI용 IAM OIDC Role(§8 7단계, §9-3) | `modules/backend-cicd`(신규) 작성 — `modules/frontend-cicd`와 같은 패턴(GitHub OIDC, `StringLike`+와일드카드 신뢰 조건)이지만 환경 접미사 없이 서비스당 Role 1개, `dev`+`main` 브랜치를 동시에 신뢰(ECR이 계정 공용이라 환경별로 나눌 이유가 없음). ECR push 권한(`PutImage`/`InitiateLayerUpload` 등)을 해당 서비스 리포지토리 ARN으로만 제한, `GetAuthorizationToken`만 리소스 스코핑 불가라 `*`. `environments/bootstrap`에서 `slash-api`/`slash-nlu`/`slash-llm` 3개 apply(ECR과 같은 이유로 bootstrap 소유) | `aws iam get-role`로 `slash-api-cicd`의 신뢰 정책이 `repo:LikeLionTeam4*/slash-api*:ref:refs/heads/{dev,main}`로 정확히 제한된 것 확인. 실제 워크플로 자체는 아직 없음(이슈 #11 대기) — Role만 미리 준비 |
| 2026-08-12 | dev 전체 리소스 스캔 + Ingress 부수효과 발견/수정 | `aws resourcegroupstaggingapi get-resources`(Project=slash)로 전체 인벤토리 확인 중, `image.tag`가 빈 채로 `ingress.enabled=true`였던 `slash-api`가 **실제 ALB(`k8s-default-slashapi-...`, 과금 중, healthy 타겟 0개)를 만들어낸 것을 발견** — 아무도 명시적으로 켠 적 없는 부수효과. `helm/slash-api/values-dev.yaml`의 `ingress.enabled`를 `false`로 낮춰 git에서부터 커밋 → ArgoCD가 198초 만에 sync해 Ingress 리소스 prune → ALB Controller가 실제 ALB까지 자동 정리 | `kubectl get ingress`로 리소스 사라짐 확인, `aws elbv2 describe-load-balancers`로 ALB 0개 재확인. **교훈**: `kubectl delete`로 직접 지우면 selfHeal이 즉시 되살리므로(§4 2026-08-12 orphan ALB 항목과 동일 원리), git의 소스(values 파일)를 고치는 것만이 durable fix — 실제 이미지가 준비되면(이슈 #11) `image.tag`를 채우면서 `ingress.enabled`도 같이 `true`로 되돌릴 것 |
| 2026-08-12 | **dev 전체 destroy** (§8 마무리) | K8s 레벨부터 정리: `argocd/applications-dev/` 3개 삭제 → **Application 삭제가 관리 리소스를 자동 prune하지 않는다는 것 발견**(cascade finalizer 미설정) → Deployment/HPA/Service/ServiceAccount를 label selector로 직접 삭제 → `helm uninstall`로 karpenter/aws-load-balancer-controller/metrics-server/argocd 순서로 제거(CRD는 helm 정책상 보존) → `karpenter/dev/nodepool.yaml` 삭제. 이어서 Terraform destroy를 의존관계 역순으로: `observability`(3) → `eks`(19) → `database`(7, RDS Multi-AZ라 5분25초 소요) → `cognito`(3) → `network`(40, 이번에도 flow-log 버킷에 97개 버전 쌓여 있어 미리 비우고 destroy). ECR/백엔드 CI Role/AWS Budgets는 계정 공용이라 그대로 유지 | 전부 "N destroyed, 0 errors"로 완료. `resourcegroupstaggingapi`(Project=slash 태그)로 재스캔했을 때 NAT 2개·dev VPC·dev Cognito Pool·EC2 인스턴스 1개가 아직 남은 것처럼 보여서 각 서비스 API로 직접 재확인 — NAT는 `State: deleted`, VPC/Cognito Pool은 `NotFound`, 인스턴스는 빈 결과로 **전부 실제로는 이미 삭제됨** 확인. **교훈**: `resourcegroupstaggingapi`는 태그 인덱스 캐시라 삭제 직후 몇 분간 지연될 수 있음 — destroy 직후 최종 확인은 이 API보다 `describe-vpcs`/`describe-nat-gateways`/`describe-user-pool` 같은 해당 서비스 API를 직접 쓸 것 |
| 2026-08-13 | 부트캠프 계정 재발급 발견 및 대응(`727646470302` → `061039804626`) | `dev/*` backend가 옛 계정 S3 버킷을 참조 중이라 `terraform init`부터 막힌 것을 발견 — `bootstrap`/`local`은 이미 새 계정으로 재구성돼 있었는데(오늘 client_id 트러블슈팅의 배경, 위 §4 항목) `dev`만 옛 계정 참조가 안 옮겨진 상태였음. `environments/dev/{network,cognito,database,eks,observability}/main.tf`의 backend bucket 5곳, `helm/{slash-api,slash-nlu,slash-llm}/values.yaml`의 ECR `repository` 3곳, `helm/slash-api/values-dev.yaml`의 ACM `certificate-arn` 계정 부분을 전부 `061039804626`으로 치환 | `aws sts get-caller-identity`로 현재 계정 확인, `aws ecr describe-repositories`로 실제 ECR이 새 계정에 있는 것 확인(치환 전엔 로컬 포함 모든 환경의 ECR push/pull이 실제로는 깨져 있었던 상태) |
| 2026-08-13 | `dev` 환경 재구축 (network→cognito→database→eks→observability, 계정 재발급 이후 1차) | §8과 동일한 순서·모듈로 재apply: network 40개, cognito 4개(client_id 포함 — §4 항목 실전 검증), database 7개(RDS Multi-AZ, 13분18초), eks 19개(클러스터 생성 8분43초) → **ACM 인증서 DNS 검증에서 `reading Route 53 Hosted Zone (Z03858108FMADVU36PUA): couldn't find resource` 에러**(zone도 계정 재발급으로 ID가 바뀌었는데 `environments/dev/eks/domain.tf`엔 옛 zone ID가 정적 값으로 남아 있었음 — ECR/backend bucket과 같은 패턴의 누락) → `bootstrap` output에서 새 zone ID(`Z02458772F0ED1QG30X6D`) 확인해 교체 후 재plan(2 to add만 남음) → 재apply로 인증서 검증 완료(ISSUED). observability 3개 apply | `kubectl get nodes`로 3개 노드 `Ready` 확인. `helm/slash-api/values-dev.yaml`의 certificate-arn도 실제 발급된 새 ARN(`dae5ed19-...`)으로 갱신 |
| 2026-08-13 | ArgoCD + ALB Controller + dev Application 재설치, CI Role 확인 | `aws eks update-kubeconfig --name slash-eks-dev` → ArgoCD Helm 설치(argocd 네임스페이스) → `argocd/applications-dev/` 3개 `kubectl apply` → 전부 `Synced` 확인. ALB Controller는 `kube-system/aws-load-balancer-controller` ServiceAccount(IRSA role-arn 어노테이션)를 직접 생성 후 `eks/aws-load-balancer-controller` Helm 설치(2/2 Running). `environments/bootstrap`의 `modules/backend-cicd`(CI IAM Role 3개, ECR push용)는 `terraform plan`이 "No changes"라 새 계정에도 이미 정상 적용돼 있었음을 확인 | 파드 5개(`slash-api` 2, `slash-nlu` 2, `slash-llm` 1) 전부 `InvalidImageName` — 예상된 상태(`image.tag` 아직 빈 값, 이슈 #11 Dockerfile 대기). Helm→ArgoCD→K8s 배선 자체는 정상 작동 확인, 이슈 #11 완료되는 대로 팀원 CI/CD 배포 시 정상 반영되는지 검증 예정 |

### 보안그룹 description의 ASCII 제약 (2026-08-04)

`environments/local/network` 첫 apply 때 `aws_security_group.eks`/`aws_security_group.db`와 그 규칙 5개, 총 7개가 실패했다.

```
Error: creating Security Group (slash-eks-sg-local): ...
api error InvalidParameterValue: Value (EKS 노드/파드 baseline SG ...)
for parameter GroupDescription is invalid. Character sets beyond ASCII are not supported.
```

- **원인**: AWS EC2의 `CreateSecurityGroup`/`AuthorizeSecurityGroupIngress` API는 `GroupDescription`과 규칙 `description`에 **ASCII만 허용**한다. `modules/network/main.tf`에 한글 설명을 그대로 써서 발생.
- **영향 범위**: 나머지 31개(VPC, 서브넷, IGW, NAT, 라우트테이블, S3 Gateway Endpoint, Flow Log)는 이 제약과 무관해서 정상 생성됨 — 실패는 SG 관련 7개로 국한.
- **조치**: 해당 7개 리소스의 `description`을 영문으로 교체, 원래 한글 설명은 옆에 Terraform 주석으로 보존. 재apply로 나머지 7개만 추가 생성(다른 31개는 이미 state에 있어서 안 건드림).
- **교훈**: AWS 리소스 중 일부 필드(SG description이 대표적)는 비ASCII를 거부한다 — 사용자에게 보여줄 게 아닌 AWS API 파라미터에는 한글을 쓰지 않는다.

### `aws_elasticache_cluster`는 AUTH 토큰을 지원하지 않음 (2026-08-04, `terraform validate` 단계에서 발견)

```
Error: Unsupported argument
  on valkey.tf line 25, in resource "aws_elasticache_cluster" "main":
  25:   auth_token = random_password.valkey_auth.result
An argument named "auth_token" is not expected here.
```

- **원인**: `auth_token`/`transit_encryption_enabled`는 `aws_elasticache_replication_group`에만 있는 인자다. `aws_elasticache_cluster`(단일 노드 전용 리소스)는 이 필드 자체가 스키마에 없다.
- **조치**: 노드가 1개뿐이라도(`num_cache_clusters = 1`, `automatic_failover_enabled = false`) `aws_elasticache_replication_group`으로 만들어야 AUTH 토큰을 붙일 수 있다.
- **교훈**: ElastiCache는 "복제 그룹이냐 아니냐"보다 "AUTH/암호화가 필요하냐"가 리소스 선택 기준 — 노드 개수만 보고 `aws_elasticache_cluster`를 고르면 안 된다.

### versioning 켜진 S3 버킷은 `terraform destroy`로 바로 안 지워짐 (2026-08-04)

CloudTrail 검증 후 정리하며 `aws_s3_bucket.cloudtrail`을 destroy했더니 실패했다.

```
Error: deleting S3 Bucket (slash-cloudtrail-727646470302): ...
api error BucketNotEmpty: The bucket you tried to delete is not empty.
You must delete all versions in the bucket.
```

- **원인**: `aws_s3_bucket_versioning.cloudtrail`이 `Enabled`라서, 트레일을 켠 지 1분도 안 돼 CloudTrail이 `AWSLogs/.../CloudTrail/` 폴더 마커 객체를 이미 하나 써놨다. 버저닝된 버킷은 오브젝트를 지워도 버전이 남기 때문에(delete marker만 쌓임) `force_destroy` 없이는 일반 `DeleteBucket`이 안 먹는다. 이 모듈엔 `force_destroy`가 없다.
- **조치**: `aws s3api list-object-versions`로 버전 확인 → `aws s3api delete-object --version-id ...`로 버전 자체를 삭제 → 버킷 재destroy로 완료.
- **교훈**: `local/frontend`처럼 초반부터 트래픽/콘텐츠가 쌓이는 버킷뿐 아니라, CloudTrail·flow_logs처럼 "만들자마자 뭔가 로그를 쓰는" 버킷도 검증 후 바로 지울 계획이면 모듈에 `force_destroy = true`를 켜두는 게 낫다 — 매번 수동으로 버전 지우는 걸 반복하고 싶지 않다면.

### `aws_db_instance.id`는 CloudWatch가 기대하는 식별자가 아님 (2026-08-04)

`local/database` apply 직후 `rds_instance_id` output이 `db-NFFMMSMQHLCWEH7Z4YAVNSOPFA` 형태였다. `aws rds describe-db-instances`로 대조해보니 이건 `DbiResourceId`고, 실제 `DBInstanceIdentifier`는 `slash-rds-local`이었다.

- **원인**: `modules/database/outputs.tf`가 `aws_db_instance.main.id`를 노출했는데, 이 provider 버전에서 `id`는 `identifier`(사용자가 지정한 이름)가 아니라 `resource_id`(`DbiResourceId`, AWS 내부 리소스ID)와 같은 값을 반환한다. CloudWatch `AWS/RDS` 네임스페이스의 `DBInstanceIdentifier` 차원은 반드시 전자(`slash-rds-local`)를 써야 한다.
- **영향**: 고치기 전 값으로 observability를 apply했다면 알람이 생성은 되지만 존재하지 않는 차원 값을 가리켜서 메트릭이 절대 안 들어오고 영원히 `INSUFFICIENT_DATA`로 남았을 것 — 콘솔에서 보면 "알람이 있는데 작동을 안 함" 상태라 원인 찾기 어려웠을 것.
- **조치**: `aws_db_instance.main.id` → `.identifier`로 수정. database 재apply(0 added/changed, output만 갱신) 후 observability를 apply해서 `slash-rds-cpu-local` 알람이 실제 CPU 데이터를 받는 것까지 확인.
- **교훈**: `aws_db_instance`에서 "그 인스턴스를 가리키는 문자열"이 필요하면 `.id`를 쓰지 말고 무슨 값이 필요한지(사용자 지정 identifier vs AWS 내부 리소스ID)에 따라 `.identifier`/`.resource_id`를 명시적으로 골라야 한다 — 두 값 모두 "그럴듯한 ID처럼" 보여서 plan 단계에서는 문제가 안 드러난다.

### EKS 관리형 노드그룹의 launch template엔 `iam_instance_profile`을 지정하면 안 됨 (2026-08-04)

`local/eks` apply 중 노드그룹 생성 단계(20개 중 마지막)에서 실패했다.

```
Error: creating EKS Node Group (slash-eks-local:slash-eks-general-local): ...
InvalidParameterException: Launch template ... should not specify an instance profile.
The noderole in your request will be used to construct an instance profile.
```

- **원인**: `modules/eks/node_group.tf`의 `aws_launch_template.node`가 `iam_instance_profile { arn = aws_iam_instance_profile.node.arn }`을 명시하고 있었다. EKS 관리형 노드그룹(`aws_eks_node_group`)은 `node_role_arn`으로 인스턴스 프로필을 **자체 구성**하기 때문에, 커스텀 launch template에 별도로 지정하면 EKS API가 거부한다.
- **영향 범위**: 클러스터·OIDC·Karpenter IAM 역할(9개)까지는 이 launch template과 무관해서 정상 생성됨 — 실패는 노드그룹 1개(및 그 뒤 순서였던 마무리 리소스들)로 국한.
- **조치**: launch template에서 `iam_instance_profile` 블록만 제거(`aws_iam_instance_profile.node` 리소스 자체는 outputs와 향후 Karpenter 노드용으로 계속 쓰이므로 유지). 재apply로 노드그룹까지 정상 생성, `ACTIVE` 상태와 desired size 3 확인.
- **교훈**: EKS 관리형 노드그룹 + 커스텀 launch template 조합에서는 AMI/보안그룹/메타데이터 옵션 등은 launch template에 넣어도 되지만, **IAM 인스턴스 프로필만은 넣으면 안 된다** — `node_role_arn`이 이미 그 역할을 한다.

### GitHub OIDC provider가 계정에 이미 존재 — 다른 팀 소유였음 (2026-08-05)

프론트엔드 CI/CD용 IAM Role을 만들기 전 `aws iam list-open-id-connect-providers`로 확인했더니 `token.actions.githubusercontent.com`이 이미 등록돼 있었다.

```
Arn: arn:aws:iam::727646470302:oidc-provider/token.actions.githubusercontent.com
Tags: [{"Key": "Name", "Value": "Team1-front-github-oidc"}]
CreateDate: 2025-08-01
```

- **원인**: 이 계정(`727646470302`)은 부트캠프 여러 팀이 공유하는 계정이다(`aws iam list-open-id-connect-providers` 결과 EKS용 OIDC provider가 60개 넘게 있음 — 각 팀·각 클러스터마다 하나씩). GitHub Actions OIDC provider도 URL당 계정에 1개만 등록 가능한데, `Team1`이 이미 자기네 프론트엔드 CI용으로 만들어놓은 걸 우리가 발견한 것.
- **영향**: `docs/aws-architecture.md` §9-1이 원래 "PH-03 시점에 이 provider를 만든다"고 적어놨었는데, 그대로 Terraform `resource`로 만들려고 했으면 API가 "이미 존재" 에러를 냈을 것이고, 혹시 `import`로 가져와서 관리했다면 우리 쪽에서 `destroy`할 때 다른 팀의 provider를 같이 지워버릴 뻔했다.
- **조치**: `aws_iam_openid_connect_provider`를 리소스로 만들지 않고 `data "aws_iam_openid_connect_provider"`로 읽기 전용 참조만 하도록 설계(`modules/frontend-cicd`). §9-1 문서도 이 사실에 맞춰 수정.
- **교훈**: 여러 팀이 공유하는 계정에서는 "계정당 1개"인 리소스(OIDC provider, 나중에 다른 것도 있을 수 있음)를 만들기 전에 **먼저 `list`로 이미 있는지 확인**하는 습관이 필요하다 — 실습용 개인 계정이라고 가정하고 그냥 만들면 다른 팀 것과 충돌하거나, 최악의 경우 destroy 때 남의 리소스를 지운다.

### `slash-web`의 `main`이 빈 스텁 브랜치였음 (2026-08-05)

첫 배포 테스트 때 `main`을 타겟으로 워크플로를 붙였는데, merge 직후 `npm ci` 단계에서 바로 실패했다.

```
##[error]Dependencies lock file is not found in /home/runner/work/slash-web/slash-web.
Supported file patterns: package-lock.json,npm-shrinkwrap.json,yarn.lock
```

- **원인**: `git ls-tree origin/main --name-only`로 확인해보니 `main`엔 `README.md` 하나뿐이었다. `dev`가 `main`보다 49커밋 앞서있다는 건 이미 알고 있었지만(그래서 `dev` 전체를 merge하지 않고 워크플로 파일만 올리는 쪽을 택했었다), 그 차이가 "커밋 몇 개"가 아니라 **`main`에 앱 코드 자체가 없다**는 뜻인 줄은 몰랐다 — 실제 개발은 전부 `dev`에서 진행 중.
- **조치**: `modules/frontend-cicd`의 `github_branch`를 `dev`로 바꿔 재apply, 워크플로 트리거도 `push: branches: [dev]`로 옮김. 코드에 `팀이 dev->main 첫 정식 릴리스하면 main으로 되돌릴 것` TODO 남김.
- **교훈**: 워크플로를 어떤 브랜치에 붙이기 전에 **그 브랜치에 실제로 뭐가 있는지**(`git ls-tree <branch> --name-only`) 확인해야 한다 — "커밋 수 차이"만 보고 "그래도 브랜치는 유효하겠지"라고 가정하면 안 된다.

### GitHub의 OIDC "immutable IDs"로 `sub` 클레임에 숫자 ID가 붙어 나옴 (2026-08-05)

`dev`로 브랜치를 바꾼 뒤에도 `sts:AssumeRoleWithWebIdentity`가 계속 `AccessDenied`로 거부됐다. trust policy를 몇 번 확인해도 `repo:LikeLionTeam4/slash-web:ref:refs/heads/dev`로 정확히 맞아 보였는데, CloudTrail 이벤트 히스토리(`aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity`)로 실제 거부된 요청의 신원을 보니 원인이 나왔다.

```
Username: repo:LikeLionTeam4@305683394/slash-web@1315812460:ref:refs/heads/dev
```

- **원인**: `LikeLionTeam4` 조직은 GitHub Actions OIDC의 "immutable IDs" 기능이 켜져 있어서, `sub` 클레임이 `repo:<org>/<repo>:ref:...`가 아니라 `repo:<org>@<org_id>/<repo>@<repo_id>:ref:...`처럼 조직/저장소 이름 뒤에 불변 숫자 ID가 붙어서 나온다. `StringEquals`로 이름만 정확히 매칭하려던 조건이 애초에 절대 안 맞는 조건이었다.
- **조치**: `modules/frontend-cicd`의 조건을 `StringEquals` → `StringLike`로 바꾸고, `repo:${org}*/${repo}*:ref:refs/heads/${branch}`처럼 조직명·저장소명 뒤에 와일드카드를 붙였다 — ID가 붙어 나오든 안 붙어 나오든 매칭되게. 숫자 ID(`305683394`, `1315812460`)를 그대로 하드코딩하는 대안은 재사용성이 떨어지고 다른 저장소엔 아예 안 맞아서 배제.
- **교훈**: GitHub OIDC 연동에서 trust policy가 "설정만 봐서는 맞는데 계속 거부"될 때는, `aws cloudtrail lookup-events`로 **실제 거부된 요청의 `Username`/`principalId`**를 보는 게 제일 빠르다 — CloudTrail 트레일 리소스가 없어도(우리는 §4 앞부분에서 이미 destroy함) 계정은 최근 90일 관리 이벤트를 항상 무료로 보관하고 있어서 `lookup-events`로 조회 가능하다.

### SPA 라우팅 폴백이 404만 처리해서 403은 raw XML이 그대로 노출됨 (2026-08-05)

`https://local.sbsh.cloud/new`를 새로고침하면 CloudFront/S3의 raw `AccessDenied` XML이 그대로 떴다(react-router가 렌더링할 기회조차 없이).

```
$ curl -sI https://local.sbsh.cloud/new
HTTP/2 403
content-type: application/xml
```

- **원인**: `modules/frontend-hosting`의 `custom_error_response`가 `404`(NoSuchKey)만 `/index.html`로 재작성하고 있었다. 그런데 이 버킷 정책은 CloudFront OAC에 `s3:GetObject`만 주고 `s3:ListBucket`은 안 줘서, S3가 존재하지 않는 키를 요청받으면 (버킷 안에 뭐가 있는지 추측 못 하게) `404`가 아니라 **`403 AccessDenied`**를 돌려준다 — S3의 알려진 표준 동작. 그래서 SPA 폴백이 한 번도 발동한 적이 없었고, `/new`뿐 아니라 새로고침으로 진입 가능한 다른 클라이언트 라우트 전부 같은 문제였다.
- **조치**: `custom_error_response` 블록을 하나 더 추가해서 `403`도 동일하게 `/index.html`로 재작성(`response_code = 200`). `local/frontend` 재apply(CloudFront 배포 수정 2개 리소스, 파괴 없음, 반영까지 약 1분).

### Cognito User Pool은 `PASSWORD` 없이 `EMAIL_OTP` 단독으로 못 만듦 (2026-08-05)

`modules/cognito`의 `aws_cognito_user_pool`을 `sign_in_policy.allowed_first_auth_factors = ["EMAIL_OTP"]`(비밀번호 없이 이메일 OTP만)로 apply했더니 생성 자체가 거부됐다.

```
Error: creating Cognito User Pool (slash-users-local): ...
InvalidParameterException: Password should be configured as one of the allowed first auth factors.
```

- **원인**: Cognito API는 `sign_in_policy`에 `PASSWORD`가 반드시 포함되어 있어야 한다 — `EMAIL_OTP` 등 다른 1차 인증 수단은 `PASSWORD`에 **추가**할 수만 있고, 완전히 대체할 수는 없다(2026-08 시점 API 제약). "비밀번호 없는 로그인"을 원한다고 해서 User Pool 레벨에서 비밀번호 옵션 자체를 없앨 수는 없다는 뜻.
- **영향**: User Pool·Client·Domain 3개 리소스 중 User Pool 생성 단계에서 막혀서 나머지 2개는 아예 시도되지도 않았다(순서상 가장 먼저라 영향 범위가 제일 큼).
- **조치**: `allowed_first_auth_factors` 기본값을 `["PASSWORD", "EMAIL_OTP"]`로 변경해서 재apply, 3개 전부 성공. `slash-web`의 `LoginPage.tsx`는 애초에 `PASSWORD` 챌린지를 요청하지 않고 `EMAIL_OTP`만 쓰므로, User Pool이 `PASSWORD`를 "허용"하고 있어도 실제 로그인 화면에 비밀번호 입력란이 나오는 건 아니다 — AWS API 제약과 실제 앱 UX는 별개.
- **교훈**: Cognito의 "1차 인증 수단"은 User Pool이 뭘 **허용**하는지 목록이지, 클라이언트가 뭘 **강제로 요구**받는지가 아니다. `PASSWORD`를 목록에 넣는 게 "비밀번호 로그인을 지원한다"는 뜻은 아니고, 그냥 Cognito가 요구하는 최소 조건을 채운 것 — 실제 어떤 챌린지를 쓸지는 앱(프론트/`slash-api`)이 `InitiateAuth` 호출 시 고르는 문제다.
- **교훈**: CloudFront+S3 OAC+SPA 조합에서는 **404뿐 아니라 403도 같이 처리**해야 한다 — `s3:ListBucket`을 안 주는 게(권장되는 최소 권한) 오히려 에러 코드를 바꿔버리는 부작용이 있다는 걸 몰랐음.

### 로컬(Apple Silicon) 빌드 이미지와 EKS 노드 아키텍처 불일치 (2026-08-11)

`mock-services/`의 세 이미지를 `mock-20260811` 태그로 push하고 EKS에 파드로 배포했더니 전부 `Error` 상태로 재시작을 반복했다.

```
$ kubectl logs -l app=slash-api-mock
exec /usr/local/bin/python: exec format error
```

- **원인**: 이미지를 빌드한 맥북이 Apple Silicon(arm64)이라, `docker build`(플랫폼 미지정)가 기본으로 arm64 이미지를 만들었다. 반면 `modules/eks/node_group.tf`의 `node_instance_type` 기본값(`t3.medium`)은 x86_64(amd64) 계열이라, 노드 커널이 arm64 바이너리를 실행하지 못해 즉시 죽었다. EKS는 이미지 pull 자체는 성공(`kubectl describe pod`에 `Pulled` 이벤트가 정상적으로 찍힘)하기 때문에, 이미지가 없거나 권한이 없는 문제가 아니라 아키텍처만 안 맞는 경우 로그를 직접 봐야 원인이 보인다.
- **부수적으로 겪은 문제**: `docker build --platform linux/amd64`/`docker pull --platform linux/amd64`를 줘도 Colima의 legacy builder(`docker buildx`가 기본 비활성)가 이를 무시하고 계속 arm64로 빌드했다. `~/.docker/cli-plugins/docker-buildx`가 Docker Desktop 앱을 가리키는 깨진 심볼릭 링크였던 게 원인 — `brew install docker-buildx` 후 `/opt/homebrew/opt/docker-buildx/bin/docker-buildx`로 링크를 다시 걸고 `docker buildx create --use`로 별도 builder를 띄우고 나서야 `--platform linux/amd64`가 실제로 적용됐다.
- **조치**: `mock-20260811-amd64` 태그로 buildx 재빌드 → push → `kubectl set image`로 배포 교체, 3개 서비스 전부 `Running` + `/health` 응답 확인.
- **교훈**: Apple Silicon 맥북에서 빌드한 이미지를 x86_64 EKS 노드에 올릴 계획이면, 로컬 `docker build`만으로는 부족하다 — `docker buildx build --platform linux/amd64`(buildx가 정상 연결돼 있는지 먼저 확인)를 쓰거나, CI(GitHub Actions 러너는 보통 amd64)에서 빌드하는 걸 기본으로 삼는 게 안전하다. 노드그룹을 Graviton(arm64, `t4g.*`)으로 바꾸는 대안도 있지만, 실제 서비스 CI가 amd64 러너를 쓸 가능성이 높아 이번엔 이미지 쪽을 고쳤다.

### ALB Controller가 만든 ALB는 Terraform이 모른다 — 클러스터 destroy 전에 먼저 지워야 함 (2026-08-11)

ALB Controller 검증용으로 만든 테스트 Ingress를 그대로 둔 채 EKS 클러스터를 destroy하려던 참에 짚은 문제.

- **원인**: `alb.ingress.kubernetes.io/scheme: internet-facing` Ingress를 적용하면 ALB Controller가 **Terraform이 전혀 모르는 실제 ALB/타겟그룹/리스너**를 AWS에 만든다. 클러스터(즉 ALB Controller 파드)를 먼저 지워버리면, 그 컨트롤러가 담당 리소스를 정리할 기회 자체가 없어져서 ALB가 **고아 자원으로 계정에 영원히 남는다** — Terraform state에도 없고 콘솔에서 우연히 찾기 전까지는 계속 과금된다.
- **조치**: 클러스터 destroy 전에 `kubectl delete ingress <name>`을 먼저 실행 → `aws elbv2 describe-load-balancers`로 ALB가 실제로 사라진 것까지 확인 → 그다음에 `terraform destroy` 진행. 이번엔 문제없이 정리됨.
- **교훈**: ALB/NLB Controller, ExternalDNS처럼 **K8s 리소스가 트리거해서 AWS 자원을 만드는 컨트롤러**를 쓰는 클러스터는, destroy 순서에 "그 컨트롤러가 만든 K8s 리소스부터 지우기"를 항상 첫 단계로 넣어야 한다 — Terraform destroy만 믿으면 놓친다.

### ArgoCD selfHeal이 destroy 전 `kubectl delete ingress`를 즉시 되살려 orphan ALB를 다시 만듦 (2026-08-12)

§7 시나리오 5종 검증을 마치고 §4(위 항목)에 적어둔 절차대로 `kubectl delete ingress slash-api` → `aws elbv2 describe-load-balancers`로 ALB가 사라진 것 확인 → 클러스터 destroy까지 진행했는데, destroy가 끝난 뒤 다시 확인해보니 **다른 ARN을 가진 새 ALB가 하나 더 떠 있었다**(CreatedTime이 Ingress를 지운 시각보다 나중).

```
DNSName: k8s-default-slashapi-8e47ccebfe-2012171098...  (기존에 확인했던 것과 다른 suffix)
CreatedTime: 2026-08-12T01:44:41Z
```

- **원인**: §7-4에서 검증했던 바로 그 `syncPolicy.automated.selfHeal: true`가 원인이었다 — `kubectl delete ingress`로 Ingress를 지우자마자(수 초 안에, §7-4에서 측정한 것과 동일한 속도로) ArgoCD가 git 상태와의 drift로 인식하고 **즉시 재생성**했다. 그 순간 ALB Controller가 아직 살아있어서 재생성된 Ingress에 맞춰 **새 ALB를 또 프로비저닝**했고, 그 직후(재확인 없이) ArgoCD/ALB Controller를 helm uninstall하고 클러스터를 destroy해버려서, 이 두 번째 ALB는 컨트롤러가 정리할 기회를 영영 잃고 AWS 계정에 고아로 남았다. Terraform도 이 리소스를 모른다(§4 "ALB Controller가 만든 ALB는 Terraform이 모른다"와 동일한 근본 원인).
- **조치**: `aws elbv2 delete-load-balancer` → `delete-target-group`으로 ALB/타겟그룹 수동 삭제. 연관 보안그룹 2개(`k8s-default-slashapi-...`, `k8s-traffic-slashekslocal-...`)도 지우려 했으나 `slash-eks-sg-local`(Terraform 관리 EKS 클러스터 SG)의 인바운드 규칙이 포트 8080에서 그중 하나(`k8s-traffic-...`)를 참조하고 있어 `DependencyViolation`으로 1차 실패 — `aws ec2 revoke-security-group-ingress`로 그 규칙(ALB Controller가 동적으로 추가한 것, Terraform state엔 없음)부터 지운 뒤 재시도해서 보안그룹 2개까지 정리 완료. 이후 계정 전체를 스윕해서 우리 VPC(`vpc-0e99fcc8dcea839a0`) 소속 리소스가 더 없는 것, 나머지는 전부 다른 팀 것(다른 VPC ID)인 것까지 확인.
- **교훈**: `selfHeal: true`가 켜진 Application 앞에서는 "리소스를 수동으로 지우고 확인 → 그 다음 단계로 진행"하는 절차 자체가 안전하지 않다 — 확인하는 그 사이에 이미 되살아날 수 있다(§7-4에서 본 것처럼 재생성은 수 초 단위로 빠르다). destroy 순서에 GitOps 컨트롤러가 끼어 있으면, K8s 리소스를 지우기 전에 **먼저 `kubectl delete application <name> -n argocd`(또는 `syncPolicy.automated`를 비활성화)로 ArgoCD가 더 이상 되살리지 못하게 막고** 나서 Ingress/ALB 정리 → 클러스터 destroy 순서로 가야 한다. 이번엔 다행히 orphan이 우리 계정·우리 VPC 안이라 수동으로 찾아 지울 수 있었지만, 공유 계정에서 이런 리소스가 계속 쌓이면 비용·혼선의 원인이 된다.

### `kubectl delete application`은 관리하던 리소스를 자동으로 안 지움 (2026-08-12)

dev 전체 destroy 중 `argocd/applications-dev/`를 `kubectl delete -f`로 지운 뒤 확인해보니, `slash-api`/`slash-nlu`/`slash-llm`의 Deployment·Service·HPA·ServiceAccount가 그대로 남아있었다.

- **원인**: ArgoCD의 cascade delete(Application을 지우면 그게 관리하던 K8s 리소스까지 같이 지우는 동작)는 기본이 아니라 **`resources-finalizer.argocd.argoproj.io` 파이널라이저를 Application의 `metadata.finalizers`에 명시해야만 켜진다.** `argocd/applications/`·`argocd/applications-dev/` 매니페스트 둘 다 이 파이널라이저가 없어서, `kubectl delete application`은 ArgoCD의 "추적"만 끊었을 뿐 실제 리소스는 그대로 뒀다.
- **조치**: `kubectl delete deployment,hpa,service,serviceaccount -l 'app.kubernetes.io/name in (slash-api,slash-nlu,slash-llm)'`로 라벨 셀렉터를 이용해 직접 정리. 어차피 뒤이어 클러스터 자체(`dev/eks`)를 destroy할 예정이라 실질적 영향은 없었지만, 클러스터를 유지한 채 특정 Application만 걷어내려는 상황이었다면 리소스가 계속 떠 있는 채로 방치될 뻔했다.
- **교훈**: Application을 지워서 그 워크로드까지 걷어내고 싶으면 `kubectl delete application <name>` 한 번으로 끝난다고 가정하면 안 된다 — 매니페스트에 cascade finalizer를 미리 넣어두거나(`argocd app delete --cascade` CLI를 쓰는 것도 방법), 아니면 지운 뒤 라벨 셀렉터로 잔여 리소스를 직접 확인·정리하는 단계를 항상 절차에 넣어야 한다.

### Terraform 1.15.8엔 `-exclude` 플래그가 없음 (2026-08-11)

ECR은 남기고 나머지만 destroy하려고 `terraform destroy -exclude=...`를 시도했다가 "flag provided but not defined" 에러를 만났다.

- **원인**: `-exclude`(target의 반대, "이것만 빼고 전부")는 실제로 존재하는 플래그가 아니다 — 착각이었다. Terraform은 `-target`(이것만 포함)만 지원한다.
- **조치**: `terraform state list`로 전체 리소스를 뽑은 뒤 `grep -v`로 ECR 관련 6개를 제외하고, 나머지 16개를 전부 `-target`으로 나열해서 destroy했다.
- **교훈**: "일부만 빼고 나머지 전부"가 필요하면 `-target` 여러 개를 나열하는 것 말고 방법이 없다 — 리소스가 많으면 `terraform state list | grep -v ...`로 목록을 뽑아 스크립트로 `-target` 인자를 생성하는 편이 손으로 나열하는 것보다 안전하다.

### `awscc_cognito_managed_login_branding`의 `client_id` 생략은 import 상황 한정 우회였다 (2026-08-13)

977e585(2026-08-12)에서 `client_id`를 일부러 뺐던 게, 계정을 새로 판 뒤 처음부터 apply하니 Cognito API 자체가 생성을 거부하는 문제로 되돌아왔다.

- **원인**: 977e585 당시엔 이미 콘솔/API로 만들어져 있던 브랜딩을 `terraform import`로 가져오는 상황이었다 — 이때 `client_id`를 넣으면 CloudFormation Read 핸들러가 이 값을 안 돌려줘서 Terraform이 "생성 시점에만 되는 값이 바뀌었다"고 보고 destroy+create로 갈아엎으려 했다. 그래서 뺐고, 풀에 클라이언트가 `web` 하나뿐이라 풀 단위 브랜딩으로도 결과가 같아 문제없어 보였다. 그런데 계정을 새로 만들어 리소스가 하나도 없는 상태에서 처음부터 apply하니 `Value null at 'clientId' failed to satisfy constraint`로 생성 자체가 거부됐다 — import 우회가 아니라 신규 생성 시엔 애초에 API가 `client_id`를 필수로 요구했던 것.
- **조치**: `awscc_cognito_managed_login_branding.web`에 `client_id = aws_cognito_user_pool_client.web.id`를 복원.
- **교훈**: import 시점에 필요했던 우회를 "이 리소스엔 항상 필요 없는 값"으로 일반화하면 안 된다 — 우회의 전제(이미 존재하는 리소스에 뒤늦게 값을 채우는 상황)가 사라지면(계정 재생성 등) 그 우회 자체가 새 생성 경로를 막는 원인이 될 수 있다.

### 계정 재발급 후 `dev/eks`의 정적 Route53 zone ID가 옛 계정 값으로 남아있었다 (2026-08-13)

`dev/eks` 재apply 중 클러스터·노드그룹까지는 정상 생성됐는데 ACM 인증서 DNS 검증 단계에서 실패했다.

```
Error: reading Route 53 Hosted Zone (Z03858108FMADVU36PUA): couldn't find resource
```

- **원인**: `environments/dev/eks/domain.tf`가 `bootstrap` state의 닭-달걀 문제(§3 참고, bootstrap state가 로컬 전용이라 `terraform_remote_state`로 못 끌어옴) 때문에 `route53_zone_id`를 정적 값으로 하드코딩해 두고 있었다. 계정이 재발급되면서 `bootstrap`이 새 Route53 zone을 새 ID로 다시 만들었는데, `domain.tf`의 정적 값은 옛 계정 zone ID 그대로 남아 있었다 — ECR repository URL(helm values), tfstate backend bucket과 완전히 같은 패턴의 누락.
- **조치**: `bootstrap` 디렉터리에서 `terraform output route53_zone_id`로 새 값(`Z02458772F0ED1QG30X6D`)을 확인해 `domain.tf`에 반영, 재apply.
- **교훈**: 계정 재발급처럼 계정 전체가 바뀌는 이벤트가 생기면, "정적 값으로 박아둔 이유가 뭐였는지"(이 저장소엔 최소 3곳 — tfstate bucket, ECR URL, Route53 zone ID — 전부 같은 이유인 `terraform_remote_state`/원격 조회 불가)를 먼저 `grep`으로 훑어서 한 번에 찾는 게, 하나씩 apply하다 에러로 발견하는 것보다 낫다. `grep -rl "<옛 계정 ID>"` 한 줄이면 됐을 일이었다.

## 5. Destroy 절차

destroy는 **apply의 역순**(frontend → observability → database/eks → network → bootstrap, §1 표의 3→7→{4,5}→2→1)으로 진행한다. 순서를 안 지키면 아래처럼 막힌다.

### 5-1. `local/frontend` — 먼저

- `force_destroy = true`로 켜뒀기 때문에(§3 마지막 항목) 버킷을 수동으로 비울 필요 없이 바로 `terraform destroy` 가능.
- **이 환경을 가장 먼저 지워야 하는 이유**: `sbsh.cloud` zone 안에 이 모듈이 만든 레코드(A/AAAA/ACM 검증용 CNAME)가 들어있다. bootstrap을 먼저 지우면 zone 자체가 없어져서 frontend destroy 시 레코드를 지우려다 "zone 없음" 에러가 난다.

```bash
cd environments/local/frontend
AWS_PROFILE=slash-local terraform plan -destroy -input=false   # 먼저 확인
AWS_PROFILE=slash-local terraform destroy -input=false
```

### 5-2. `local/observability` — database보다 먼저

- RDS 인스턴스ID를 참조하는 알람이라, `database`를 먼저 지우면 참조가 끊겨 에러가 날 수 있다 — 순서상 여기부터.

```bash
cd environments/local/observability
AWS_PROFILE=slash-local terraform destroy -input=false
```

### 5-3. `local/database`, `local/eks` — network보다 먼저 (둘은 순서 무관)

- 둘 다 `network`의 서브넷·SG를 참조만 할 뿐 서로는 무관해서, 이 둘 사이의 순서는 상관없다. 단 **`network`보다는 반드시 먼저** 지워야 한다.
- `local/database`: `deletion_protection=false`, `skip_final_snapshot=true`로 오버라이드해뒀으니 바로 `terraform destroy` 가능(dev/prod는 모듈 기본값이 둘 다 반대라 destroy가 안전장치에 막힘 — 의도된 동작).
- `local/eks`: ECR 리포지토리에 이미지가 쌓여 있으면 `force_delete`를 안 켜놔서 실패할 수 있다(§4 flow_logs 버킷과 같은 패턴) — 그때는 리포지토리를 비우거나 모듈에 `force_delete = true`를 추가.

```bash
cd environments/local/database
AWS_PROFILE=slash-local terraform destroy -input=false

cd ../eks
AWS_PROFILE=slash-local terraform destroy -input=false
```

### 5-4. `local/network` — 다음

- 지금은 특별한 조치 불필요. 단 `flow_logs` 버킷(`slash-vpc-flow-logs-local-...`)에 `force_destroy`가 없어서, 로그가 쌓인 뒤에 지우려면 그때는 버킷을 먼저 비우거나 모듈에 `force_destroy`를 추가해야 함 (2026-08-04 기준 오브젝트 0개라 지금은 문제 없음).

```bash
cd environments/local/network
AWS_PROFILE=slash-local terraform plan -destroy -input=false
AWS_PROFILE=slash-local terraform destroy -input=false
```

### 5-5. `bootstrap` — 마지막

- `aws_s3_bucket.tfstate`에 `lifecycle { prevent_destroy = true }`가 걸려있어 **Terraform이 destroy 요청 자체를 거부**한다. 지우려면 `environments/bootstrap/main.tf`에서 이 lifecycle 블록을 코드에서 먼저 삭제해야 함 (별도 apply 없이, destroy 시점 코드에만 없으면 됨).
- state 버킷은 아직 어떤 환경도 S3 backend로 옮기지 않아서 오브젝트 0개 — 비우는 문제는 없음.
- **zone을 지우면 `sbsh.cloud` 전체의 DNS가 끊긴다** — 가비아는 계속 AWS의 그 4개 네임서버를 가리키고 있는데 zone이 없어지기 때문. Terraform이 막아주는 문제가 아니라 실제 서비스 영향이니 신중히 판단할 것.

```bash
cd environments/bootstrap
# main.tf에서 prevent_destroy 블록 제거 후
AWS_PROFILE=slash-local terraform plan -destroy -input=false
AWS_PROFILE=slash-local terraform destroy -input=false
```

### 5-6. `local/cognito` — 순서 무관, 아무 때나

- VPC/다른 모듈을 전혀 참조하지 않는 완전히 독립적인 환경이라, 위 5개(§5-1~5-5)와 순서 상관없이 언제 지워도 무방하다.

```bash
cd environments/local/cognito
AWS_PROFILE=slash-local terraform destroy -input=false
```

## 6. 이 문서 갱신 규칙

- RDS/Valkey, EKS/EC2, ALB Ingress 등 새 모듈을 apply하면 §1(전체 순서, 구현 열을 ✅로)과 §2(현재 적용 상태), §3(Apply 이력)에 반영한다.
- apply/destroy 중 예상 못 한 에러를 만나면 §4(트러블슈팅 기록)에 원인·조치·교훈을 남긴다 — 다음에 같은 실수를 반복하지 않는 게 목적.
- destroy 절차(§5)는 새 환경이 추가될 때마다(특히 서로 참조하는 관계가 생기면) 순서를 다시 검토한다.

## 7. 로컬 배포 시나리오 검증 (2026-08-12)

2026-08-11까지의 검증은 "config 값 변경(replicaCount) → ArgoCD 자동 sync" 왕복 1건뿐이었다. 실제 운영에서 자주 벌어질 법한 케이스를 더 대표성 있게 잡기 위해 아래 5개 시나리오를 골라 순서대로 검증한다. 각 시나리오 결과는 완료되는 대로 아래 표와 §3/§4에 기록한다.

| # | 시나리오 | 목적 | 상태 |
| --- | --- | --- | --- |
| 1 | 외부 저장소 코드 변경 시뮬레이션 (mock Dockerfile 수정 → 새 태그 build/push → `values-local.yaml` 갱신 → ArgoCD 자동 배포) | `slash-api`/`slash-nlu`/`slash-llm`에 아직 실제 Dockerfile/CI가 없는 상태에서, CI가 있었다면 벌어졌을 "코드 변경→새 이미지 배포" 전체 왕복을 재현 | ✅ 완료(2026-08-12) — 아래 참고 |
| 2 | 배포 실패 → 롤백 (존재하지 않는 이미지 태그로 배포 시도 → 실패 감지 → git revert로 복구) | ArgoCD가 실패를 어떻게 드러내는지, 되돌리는 절차가 실제로 동작하는지 확인 | ✅ 완료(2026-08-12) — 아래 참고 |
| 3 | Ingress + ALB 실제 트래픽 라우팅 (ALB Controller + ArgoCD 배포물 함께 구동) | 2026-08-11 ArgoCD 검증 라운드에서 ALB Controller를 재설치하지 않아 `Progressing`으로 남았던 Ingress를 실제 주소 할당·응답까지 닫기 | ✅ 완료(2026-08-12) — 아래 참고 |
| 4 | ArgoCD self-heal (수동 drift 후 자동 복구) | `syncPolicy.automated.selfHeal`이 git 커밋 없이 발생한 클러스터 직접 변경을 실제로 되돌리는지 확인 | ✅ 완료(2026-08-12) — 아래 참고 |
| 5 | 실제 의존성 주입 (RDS/Valkey/Cognito 값이 env/Secret으로 Deployment에 반영) | 배포 파이프라인은 되는데 서비스가 필요로 하는 실제 설정값은 안 들어가는 케이스를 사전에 잡기 | ✅ 완료(2026-08-12, Cognito 범위) — 아래 참고 |

검증 전 `environments/local/eks`를 네 번째로 재apply(§3 2026-08-12 항목)해서 클러스터를 다시 올렸다. 5개 시나리오를 모두 마친 뒤 §5 절차대로 destroy했다(ECR만 유지) — destroy 도중 ArgoCD selfHeal이 orphan ALB를 하나 더 만든 사고가 있었고, 원인·수동 정리·교훈은 §4 "ArgoCD selfHeal이 destroy 전 `kubectl delete ingress`를 즉시 되살려 orphan ALB를 다시 만듦" 항목에 남겼다.

### 7-1. 시나리오 1 — 외부 저장소 코드 변경 시뮬레이션 (완료, 2026-08-12)

`mock-services/slash-api/serve.py`의 응답에 `version` 필드(`"20260812-1"`)를 추가해 "slash-api 저장소에 실제 커밋이 있었다"는 걸 흉내냈다. `docker buildx build --platform linux/amd64`로 `mock-20260812-amd64` 태그 빌드 후 ECR push, `helm/slash-api/values-local.yaml`의 `image.tag`를 그 태그로 갱신하는 커밋을 `dev`에 push. 약 **177초 뒤** ArgoCD가 새 커밋을 감지해 자동 sync, 파드가 새 이미지로 교체됨. 새 파드에 `/health` 요청 시 `{"service": "slash-api", "status": "mock", "version": "20260812-1", "path": "/health"}` 응답으로 새 버전 반영 확인.

- 클러스터를 새로 apply한 직후라 ArgoCD/Application 3개도 처음부터 재설치·재등록해야 했다(§3 2026-08-12 ArgoCD 설치 항목과 동일 절차, `argocd/README.md` 참고) — destroy→재apply 사이에는 ArgoCD 자체도 클러스터와 함께 사라지므로 매번 다시 설치해야 한다는 걸 재확인.
- 이번 라운드도 2026-08-11의 replicaCount 테스트와 마찬가지로 폴링에 macOS `timeout` 커맨드 대신 `SECONDS` 내장변수를 사용해 문제없이 진행됨.
- 이 시나리오로 "config 값만 바뀐 배포"(2026-08-11)와 "실제 새 아티팩트가 배포되는" 경우가 ArgoCD 입장에서 동일하게(이미지 태그 변경 → 롤링 업데이트) 처리된다는 것도 확인됨 — 별도 파이프라인이 필요 없음.

### 7-2. 시나리오 2 — 배포 실패 → 롤백 (완료, 2026-08-12)

`values-local.yaml`의 `image.tag`를 ECR에 존재하지 않는 태그(`mock-20260812-typo-amd64`)로 바꿔 커밋+push. ArgoCD가 약 296초 뒤 감지해 sync → 새 파드가 `ImagePullBackOff`(`kubelet` 이벤트: `failed to resolve reference ...: not found`)로 대기하는 동안, **기존 파드는 그대로 `Running`을 유지**해 다운타임 없이 실패가 격리됨(Deployment의 기본 롤링업데이트 전략 덕분). `git revert`로 되돌리는 커밋을 push하자 약 160초 뒤 ArgoCD가 재sync해 정상 이미지로 롤백, `/health` 응답도 `version: "20260812-1"`(시나리오 1의 정상 버전)으로 원복 확인.

- **주의할 점**: ArgoCD `Application`의 `status.health.status`는 배포 실패 이후에도, 롤백 이후에도 계속 `Progressing`으로 남아있었다 — 원인은 배포 실패와 무관하게 `Ingress` 리소스가 (이 라운드는 ALB Controller를 설치하지 않아서, §7-3 참고) `Progressing`으로 고정돼 있어 리소스 트리 전체의 최악값을 반영하는 Application 헬스를 끌어내리고 있었기 때문. `kubectl get application slash-api -o jsonpath='{.status.resources[*]}'`로 리소스별 헬스를 뜯어보면 `Deployment`는 정확히 `Healthy`/`Progressing`을 반영하고 있었음 — **Application 레벨 헬스만 보고 배포 성공 여부를 판단하면 안 되고, 리소스별 헬스를 봐야 한다**는 게 이번 시나리오의 핵심 교훈.
- `ImagePullBackOff`는 `kubectl describe pod`의 Events(`Failed`, `BackOff`)로 바로 드러나서 원인 파악 자체는 빨랐음 — Argo UI/CLI만 보고 "그냥 Progressing"이라고 넘기지 말고 파드 이벤트까지 같이 봐야 한다는 점도 재확인.

### 7-3. 시나리오 3 — Ingress + ALB 실제 트래픽 라우팅 (완료, 2026-08-12)

`local/eks`가 만든 IRSA Role(`slash-alb-controller-local`)에 맞춰 `kube-system/aws-load-balancer-controller` ServiceAccount를 직접 생성(`eks.amazonaws.com/role-arn` 어노테이션)한 뒤, `eks/aws-load-balancer-controller` Helm 차트를 `clusterName=slash-eks-local`, `vpcId=<local/network output>`, `serviceAccount.create=false`로 설치 → 컨트롤러 2/2 Running. 기존에 `Progressing`으로 멈춰있던 `slash-api` Ingress가 곧바로 실제 ALB(`k8s-default-slashapi-...`)를 프로비저닝해 `ADDRESS` 필드에 DNS 이름이 채워짐. `aws elbv2 describe-target-health`로 타겟(파드 IP:8080)이 `healthy`인 것, ALB의 보안그룹이 `0.0.0.0/0:80`을 허용하는 것까지 확인.

- **첫 4분간 외부 curl이 전부 연결 실패(`000`)했다** — ALB 상태는 이미 `active`, 타겟도 `healthy`였는데 DNS(`*.elb.amazonaws.com`)가 아직 전파되지 않아서였던 것으로 보임. `aws elbv2 describe-load-balancers`/`describe-target-health`로 AWS 쪽 상태가 먼저 정상인 걸 확인한 뒤 몇 분 뒤 재시도하니 `dig`로 IP 2개가 잡히고 `curl`도 바로 `HTTP/1.1 200 OK` + `{"service": "slash-api", ..., "version": "20260812-1", ...}` 응답을 돌려줌. **교훈**: ALB 생성 직후 curl이 실패한다고 바로 설정 문제로 의심하지 말고, `describe-load-balancers`(State)와 `describe-target-health`부터 확인해 AWS 쪽은 정상인지 먼저 가른 뒤 DNS 전파를 기다리는 순서로 디버깅하는 게 맞다.
- Ingress가 이 상태가 되면서 §7-2에서 `Progressing`으로 걸려있던 `slash-api` Application의 전체 헬스도 `Healthy`로 정상화됨(리소스별 헬스가 실제로 Application 헬스에 반영되는 것도 재확인).

### 7-4. 시나리오 4 — ArgoCD self-heal (완료, 2026-08-12)

git 커밋 없이 `kubectl scale deploy slash-api --replicas=4`로 클러스터를 직접 건드려 git 상태(1)와 다른 drift를 만듦. **약 3초 만에** ArgoCD가 감지해 추가로 뜬 파드 3개를 자동으로 `Terminating`시키고 다시 1개로 되돌림 — `kubectl scale` 실행 직후 바로 확인한 파드 목록에 이미 나머지 3개가 `Terminating`으로 찍혀 있었음. `Application` 상태도 최종적으로 `sync=Synced`, `health=Healthy`로 확인.

- **§7-1/§7-2의 "새 커밋 감지"는 160~296초** 걸렸는데, 이번 **"이미 관리 중인 리소스의 drift 복구"는 3초 안팎**으로 훨씬 빨랐다. 원인 추정: 새 커밋 감지는 git 폴링 주기(기본 `timeout.reconciliation` 180초)를 타지만, self-heal은 ArgoCD가 이미 워치하고 있는 클러스터 리소스의 변경 이벤트(k8s watch/informer)에 바로 반응하기 때문 — "git → 클러스터" 방향은 폴링 지연이 있고, "클러스터가 git과 달라짐"은 거의 즉시 반응한다는 비대칭이 있다는 게 이번 시나리오의 핵심 확인 사항.
- `syncPolicy.automated.selfHeal: true`가 `argocd/applications/*.yaml`에 이미 켜져 있어 별도 설정 변경 없이 바로 검증 가능했음.

### 7-5. 시나리오 5 — 실제 의존성 주입, Cognito 범위 (완료, 2026-08-12)

`helm/slash-api`의 `deployment.yaml`은 이미 `.Values.env` 맵을 순회해 컨테이너 env로 꽂아주는 로직이 있었지만, 지금까지 어떤 `values-*.yaml`도 이 맵을 채운 적이 없었다(전부 `env: {}`) — 배선은 있는데 실제로 값이 흘러간 적은 없던 상태. `values-local.yaml`에 `environments/local/cognito`의 실제 output(`user_pool_id`, `client_id`, `issuer_url`)을 `COGNITO_*` env 3개로 채우고, mock 서버가 `COGNITO_USER_POOL_ID`를 읽어 `/health` 응답에 그대로 반영하도록 수정(`mock-20260812-cognito-amd64` 태그로 재빌드/push, §7-1과 동일 절차). 커밋 push 후 ArgoCD가 153초 만에 sync, 새 파드/외부 ALB 양쪽에서 `"cognito_user_pool_id": "ap-northeast-2_s2ZnfGrqo"`(실제 User Pool ID와 일치)까지 확인.

- **RDS/Valkey는 이번 라운드 범위에서 제외**했다 — `values-local.yaml`의 기존 주석대로 local 환경은 이 차트에서 RDS/Secrets Manager를 아예 안 띄우는 게 설계 의도이고(§13), IRSA→Secrets Manager 접근 메커니즘 자체는 2026-08-05에 임시 `irsa_test.tf`로 이미 별도 검증됐다(§3 참고) — RDS/Valkey를 다시 apply해서 중복 검증하는 대신, "값이 Deployment까지 실제로 도달하는가"라는 이번 시나리오의 목적엔 상시 유지 중인 Cognito가 더 적합한 대상이었음.
- Cognito 값(User Pool ID/Client ID)은 민감정보가 아니라서(공개 클라이언트가 사용하는 값) K8s Secret이 아닌 일반 env로 충분했다 — RDS 접속 정보처럼 실제 시크릿이 필요한 값은 여기 패턴이 아니라 §3 2026-08-05 IRSA 검증에서 쓴 Secrets Manager 경로를 따라야 한다는 것도 이번에 다시 정리됨.

## 8. dev 환경 구축 (2026-08-12, apply→검증→destroy 완료)

local에서 검증된 모듈을 dev 스펙 값으로 재사용해 `environments/dev/*`를 순서대로 만들었다. **destroy는 전 구간을 다 확인한 뒤 마지막에 한 번에** 진행 — network/eks/database처럼 뒤 단계가 앞 단계 output(서브넷 ID 등)을 참조하는 의존관계가 있어서, 매 단계마다 지웠다 다시 올리는 건 비효율적이라는 판단(local도 `network`/`cognito`는 애초에 destroy 안 하고 상시 유지하는 것과 같은 이유). **2026-08-12 저녁, 검증이 전부 끝난 뒤 dev 전체를 destroy했다 — 아래 표 상태는 "그 시점까지 이 작업들이 완료됐었다"는 기록이고, 지금은 `environments/dev/*`가 전부 미적용 상태다(§2, §3 마지막 항목 참고).**

| # | 작업 | 상태 |
| --- | --- | --- |
| 1 | `dev/network` — VPC/서브넷, NAT AZ당 1개, `backend "s3"` | ✅ 완료(2026-08-12) — 위 §3 참고 |
| 2 | `dev/cognito` — 별도 User Pool | ✅ 완료(2026-08-12) |
| 3 | `dev/database` — RDS Multi-AZ + Valkey | ✅ 완료(2026-08-12) |
| 4 | `dev/eks` — EKS 클러스터 + 노드그룹 (ECR은 bootstrap 참조) | ✅ 완료(2026-08-12) |
| 5 | `dev/observability` — CloudWatch 알람 + SNS | ✅ 완료(2026-08-12) |
| 6 | ArgoCD + dev Application 매니페스트 + ALB Controller + `api.dev.sbsh.cloud` 도메인 | 🟡 부분 완료(2026-08-12) — ArgoCD/ALB Controller/ACM 인증서까지 끝, **Route53 A레코드 연결은 실제 앱(이슈 #11) 준비 후로 의도적으로 미룸** |
| 7 | 백엔드 CI용 IAM OIDC Role(ECR push, 3개 서비스) | ✅ 완료(2026-08-12) |

- local Cognito(`slash-users-local`)와 dev Cognito는 **완전히 별도 User Pool** — network/database/eks와 같은 원칙(환경별 리소스), ECR처럼 AWS 제약으로 강제 공유해야 하는 경우가 아님. 백엔드가 지금 local 값으로 작업 중인 것과는 무관 — `values-dev.yaml`에 dev Pool 값만 새로 채우면 됨, local 쪽엔 영향 없음.
- 전 구간 apply가 끝나면 §5와 같은 순서(뒤 단계부터)로 한 번에 destroy하고 이 표 상태를 최종 갱신한다.

§9의 확장성 갭 점검 후 추가로 진행한 항목:

| # | 작업 | 상태 |
| --- | --- | --- |
| 8 | Karpenter 설치 + NodePool/EC2NodeClass (dev) | ✅ 완료(2026-08-12) — §8-1 |
| 9 | metrics-server + HPA (dev) | ✅ 완료(2026-08-12) — §8-2 |
| 10 | AWS Budgets (계정 전체, bootstrap) | ✅ 완료(2026-08-12) — §8-3 |

### 8-1. Karpenter 설치 및 스케일 검증 (완료, 2026-08-12)

IRSA Role(`slash-karpenter-controller-dev`)은 이미 4단계(`dev/eks`)에서 같이 만들어져 있었음 — Helm 설치와 NodePool/EC2NodeClass만 남아있던 상태.

- 기본/최신 안정 버전(1.1.1)으로 첫 설치 시도 → `panic: karpenter version is not compatible with K8s version 1.36`으로 파드가 `CrashLoopBackOff`. `docker manifest inspect`로 태그를 순차 탐색해 `1.10.0`이 존재하는 걸 확인 → 재설치 성공(2/2 Running)
- NodePool 최초 적용 시 `EC2NodeClass`가 `InstanceProfileReady=Unknown`에서 멈춤 → 컨트롤러 로그 확인 결과 `iam:CreateInstanceProfile`/`iam:GetInstanceProfile` 등 권한 부족(`AccessDenied`) — `EC2NodeClass.spec.role`을 쓰면 Karpenter가 인스턴스 프로필을 직접 만들고 관리하는데, 기존 IRSA 정책엔 `iam:PassRole`만 있고 프로필 관리 권한이 없었음. `modules/eks/karpenter.tf`에 `InstanceProfileManagement` 문 추가(`CreateInstanceProfile`/`TagInstanceProfile`/`AddRoleToInstanceProfile`/`RemoveRoleFromInstanceProfile`/`DeleteInstanceProfile`/`GetInstanceProfile`/`ListInstanceProfiles`, AWS 공식 Karpenter 문서와 동일하게 리소스 `*`) → `dev/eks`에 재apply(1개 정책 변경) → 94초 뒤 `EC2NodeClass Ready=True`
- NodePool에 `karpenter.k8s.aws/instance-generation Gt 2` 요구조건을 넣었더니 `operator: Gte`(작성한 적 없는 값)로 검증 에러 — 이 Karpenter 버전의 스키마 호환성 문제로 추정, 필수 조건이 아니라 제거하고 진행
- **실제 스케일 검증**: cpu 1500m × 4 replica 테스트 파드 배포 → 기존 3개 노드에 못 들어가는 2개가 Pending → **24초 만에 새 노드(t계열) 프로비저닝**, 전부 `Running` 확인. 테스트 워크로드 삭제 → **145초 뒤 그 노드가 자동으로 정리**(consolidation, `consolidateAfter: 1m`)됨을 확인
- 매니페스트는 `karpenter/dev/nodepool.yaml`(신규, `argocd/`와 같은 성격 — GitOps 대상 아닌 K8s 리소스라 커밋만 하고 `kubectl apply`로 직접 관리) + `karpenter/README.md`에 설치 절차·버전 호환성 주의사항 정리

### 8-2. metrics-server + HPA (완료, 2026-08-12)

- EKS는 `metrics-server`를 기본 포함하지 않아서 Helm으로 별도 설치(`kube-system`) — `kubectl top nodes`가 17초 만에 실제 CPU/메모리 지표를 반환하는 것 확인
- `helm/slash-api`/`slash-nlu`/`slash-llm` 세 chart 전부에 `autoscaling` values 블록(기본 `enabled: false`) + `templates/hpa.yaml` 추가. **`autoscaling.enabled=true`일 때 `deployment.yaml`이 `spec.replicas` 필드 자체를 렌더링하지 않도록** 했다 — HPA와 정적 `replicaCount`가 동시에 그 필드를 놓고 다투면(Helm/ArgoCD sync가 계속 되돌리려 하고 HPA가 계속 바꾸려 하는 충돌) 오늘 Ingress에서 겪은 selfHeal 충돌과 같은 부류의 문제가 된다는 걸 미리 피한 것
- `values-dev.yaml` 세 개 다 `autoscaling.enabled: true`로 켜서 push → ArgoCD가 155초 만에 sync → `kubectl get hpa`로 `slash-api`/`slash-nlu`/`slash-llm` 전부 생성 확인(`cpu: <unknown>/70%` — pod가 아직 없어서 예상된 상태, 이슈 #11 이후 실제 지표로 채워짐)
- `slash-llm`은 GPU 노드그룹이 생기면(#12) GPU 사용률 기반 스케일링이 더 맞을 수 있다는 점을 values.yaml에 comment로 남김 — 그건 custom-metrics-adapter가 필요해 이번 범위 밖

### 8-3. AWS Budgets (완료, 2026-08-12)

`environments/bootstrap`에 `aws_budgets_budget.monthly_cost` 1개 apply — 계정 전체가 아니라 **`Project=slash` 태그가 붙은 리소스만** `TagKeyValue` cost filter로 스코핑(계정을 다른 부트캠프 팀과 공유하고 있어서, 스코핑 안 하면 남의 지출까지 우리 알람에 섞임). 월 $100 한도에 실지출 80%/100%, 예상지출 100% 알림 3개, `baegugureview@gmail.com`으로 이메일 발송. `aws budgets describe-budget`으로 필터·한도 확인. $100은 확정치가 아니라 local/dev를 apply→destroy로 짧게 돌리는 지금 사용 패턴 기준 시작값 — 실측 지출 보고 조정 예정.

## 9. 확장성 점검 (2026-08-12)

dev 구축이 끝난 뒤 "이 구조가 실제 트래픽 증가에도 버티는가"를 점검했다.

- **환경을 늘리는 확장성은 확보됨**: 모듈 재사용(network/database/eks/cognito/backend-cicd), bootstrap의 계정 공용 자원 정리(ECR/CI Role), CIDR 간격 체계(local=10.0.0.0/16, dev=10.8.0.0/16, prod=10.16.0.0/16 예정) — dev 착수 자체가 이 패턴이 실제로 동작함을 증명.
- **부하 증가에 버티는 확장성은 설계만 있고 구현은 없었음** — 점검에서 나온 5개 갭:
  1. Karpenter 미설치 → **해소**(§8-1)
  2. HPA 없음(replicaCount 고정값) → 진행 예정(§8 표 9번)
  3. GPU 노드그룹 완전 미정(이슈 #12) — `slash-llm` 팀 확인 필요, 우리가 단독으로 못 풂
  4. RDS read replica / Valkey 스케일아웃 없음 — **의도적으로 보류**: dev엔 read replica 효과를 검증할 실제 읽기 부하가 없어서, 지금 만들면 비용만 나가고 검증 가치가 없음. 실사용자 트래픽 생기면 재검토
  5. AWS Budgets(계정 전체 비용 알림) 없음 → 진행 예정(§8 표 10번, `environments/bootstrap` 소유)
- `slash-api`의 HikariCP 커넥션 풀 설정에 "최대 replica × 풀 크기가 RDS `max_connections`의 70%를 넘지 않게 관리"라는 comment가 이미 있음 — 스케일링을 아예 고려 안 한 설계는 아니었다는 신호.

## 10. LLM 런타임(Ollama EC2) 구축 + dev 3서비스 배포 검증 + destroy (2026-08-13)

이슈 #12를 "GPU 노드그룹" → "EKS 밖 독립 EC2"로 결정 변경(§5-1)한 뒤 실제로 구축, 세 서비스(`slash-api`/`slash-nlu`/`slash-llm`) 전부 dev에 실제로 띄워보고, 검증이 끝난 뒤 이번에도 전체 destroy로 마무리했다.

### 10-1. Ollama EC2 구축 + 검증

- `modules/network`에 `ollama` 보안그룹 신설(`db` SG와 동일 패턴, EKS SG에서만 11434 인바운드) → `dev/network` 재apply
- 신규 `modules/llm-runtime` + `environments/dev/llm-runtime` — `g4dn.xlarge`, AWS Deep Learning Base GPU AMI(SSM 파라미터로 조회, NVIDIA 드라이버 내장, 루트 볼륨 75GB gp3), SSM instance profile(SSH 불필요), `user_data`(cloud-init 최초 1회)로 Ollama 설치 + `ollama pull gemma3:4b`. AMI가 "latest" SSM 파라미터를 따라가며 재생성되지 않도록 `lifecycle.ignore_changes = [ami]` 명시(stop/start로 상태 보존하는 설계 의도 보호)
- **버그 발견**: `user_data`의 `ollama pull` 단계가 `$HOME` 미설정으로 최초 실행 시 실패(`panic: $HOME is not defined`) — Ollama systemd 서비스 자체(0.0.0.0:11434 바인딩)는 정상, pull만 실패. `export HOME=/root`로 스크립트 수정, 이번 인스턴스는 SSM으로 수동 pull해 우회 검증
- `helm/slash-llm/values-dev.yaml`에 `image.tag`(PR #2 머지 커밋) + `env.OLLAMA_URL`(EC2 private IP, 정적 값) 배선 → ArgoCD sync → **실제 EKS 파드 → Ollama EC2 → 실제 Gemma3 요약 응답까지 왕복 확인**

### 10-2. slash-api/slash-nlu CI 검토

- `slash-llm`(#2)·`slash-nlu`(#4) — 팀원이 올려둔 Dockerfile+CI(test→container-build→publish-image) PR을 리뷰 후 머지. `slash-llm`은 머지 시 `.github/workflows/test.yml` 수정 포함이라 `workflow` OAuth scope 문제로 1차 머지 실패 → 사용자가 scope 추가 후 재시도로 해결
- **`slash-api`는 Dockerfile(PR #14)만 있고 CI 자체가 없던 것을 발견** — ECR에 이미지가 한 번도 push된 적 없었음. llm/nlu와 동일 패턴으로 워크플로 작성해 PR #28 오픈
  - 로컬에서 `linux/amd64` 빌드 시도 시 QEMU 에뮬레이션 SSL 핸드셰이크 실패(Gradle wrapper 다운로드 단계, 반복 재현) → 네이티브(arm64) 빌드는 통과해 에뮬레이션 문제로 확정, GitHub Actions 네이티브 러너에 맡기기로 함
  - 최초 CI 실행에서 `TimeZoneContractTest`(DB 서버 기본 timezone 검사, `pg_settings.reset_val`) 1개만 실패 — `services:` 블록이 `command` 오버라이드를 지원하지 않아 `docker-compose.yml`의 `-c timezone=Asia/Seoul`이 빠진 것으로 추정하고 수동 `docker run`으로 교체했으나 재현 안 됨(postgres 직접 조회로는 `reset_val`이 테스트 전후 모두 `Asia/Seoul`이었음)
  - **팀원이 같은 브랜치에 직접 커밋해 실제 원인 수정**: "DB 서버 기본 시간대 시험이 JVM 시간대를 보고 있었다" — GitHub Actions 러너의 JVM 기본 타임존(UTC) 문제였음. `container-build`의 헬스체크에도 DB 연결 필요함을 발견해 같이 보완. 이후 CI 전부 통과, PR #28 머지 → `sha-2b3a753d...` 이미지 ECR push 확인
- `helm/slash-nlu/values-dev.yaml`에 `image.tag`(PR #4 머지 커밋) 배선 → ArgoCD sync 후 파드가 `OOMKilled`(exit 137) — `helm/slash-nlu/values.yaml`의 128Mi/256Mi(api/llm과 동일 기본값)가 Kiwi 형태소 사전 로딩엔 부족했던 것. §13 TODO였던 "slash-nlu 컴퓨트 요구사항 미확정"이 실측으로 확인된 것 — 384Mi/768Mi로 상향 후 정상 기동, `/health`+`/internal/v1/nlu/analyze` 실제 요청 왕복까지 확인
- `slash-api`는 이미지는 준비됐지만 아직 못 띄움 — DB/Valkey/Cognito 자격증명을 Secrets Manager에서 주입받게 설계돼 있는데 `helm/slash-api/templates/deployment.yaml`이 `secretKeyRef`를 지원하지 않고(평문 `env`만 가능) IRSA Role도 미생성. 게다가 dev Valkey(ElastiCache)는 AUTH 토큰이 필요한데 `application*.yml` 어디에도 `spring.data.redis.password` 설정이 없어 인프라를 다 맞춰도 앱 코드가 막는 상태 — [이슈 #23](https://github.com/LikeLionTeam4/slash-infra/issues/23)로 정리, 다음 라운드로 이월

### 10-3. dev 전체 destroy

K8s부터 정리(ArgoCD Application 3개 삭제 → `deployment,hpa,service,serviceaccount` label selector로 직접 삭제 → `helm uninstall aws-load-balancer-controller`/`argocd`, CRD는 보존 — 이번 라운드는 Karpenter 미설치라 그 단계는 생략) → Terraform destroy를 의존관계 역순으로 진행: `llm-runtime`(4, network의 SG/서브넷 참조라 가장 먼저) → `observability`(3) → `eks`(19) → `database`(7) → `cognito`(4) → `network`(40, flow-log 버킷에 335개 버전 쌓여있어 `delete-objects`로 먼저 비움 — destroy 도중 flow log가 몇 초간 더 써서 3개가 남았고, 그 3개도 재확인 후 마저 삭제해 완료). ECR/백엔드 CI Role(3개)/AWS Budgets는 계정 공용이라 유지.

최종 확인은 지난 라운드 교훈대로 `resourcegroupstaggingapi`(캐시 지연 있음) 대신 `describe-vpcs`/`describe-nat-gateways`/`describe-db-instances`/`describe-user-pool`/`describe-replication-groups`/`describe-instances`로 직접 확인 — 전부 빈 결과 또는 `NotFound`로 실제 삭제 확인. 6개 `environments/dev/*` 모두 `terraform state list` 0개.

## 11. dev 상시 운영 전환 — CD 자동화 (2026-08-18)

**결정(2026-08-18, [이슈 #24](https://github.com/LikeLionTeam4/slash-infra/issues/24)):** 지금까지 dev는 라운드마다 apply→검증→destroy를 반복하는 테스트베드였다(§7~§10). 오늘부터 팀원이 서비스 저장소의 `dev` 브랜치에 머지하면 dev 환경에 자동 반영되도록 전환한다 — 이게 의미가 있으려면 dev가 상시로 떠 있어야 하므로, apply→destroy 반복 패턴에서 **상시 운영**으로 전환한다. 이미지 태그 자동반영 방식은 (ArgoCD Image Updater 대신) **서비스 저장소 CI가 slash-infra에 직접 커밋**하는 쪽으로 결정 — 기존 `sha-` 태그·GitOps 패턴과 가장 잘 맞음.

이번 라운드는 실제 apply 없이 **코드 준비만** 진행(다음 라운드에서 apply 예정) — 코드 변경 사항:

### 11-1. slash-api 배포 블로커(이슈 #23) 중 인프라 배선 — Terraform/Helm 준비

- Secret 동기화 방식: **External Secrets Operator(ESO)** 채택(ArgoCD Image Updater와 마찬가지로, AWS Secrets Store CSI Driver보다 GitOps 친화적이라 선택). 컨트롤러 자체에는 AWS 권한을 안 주고, 각 서비스 자신의 IRSA ServiceAccount로 `SecretStore`가 인증하는 구조 — `external-secrets/README.md`(신규, karpenter/README.md와 같은 패턴)에 수동 설치 절차 정리.
- `modules/eks/slash_api_irsa.tf`(신규): slash-api용 IRSA Role — `alb_controller.tf`/`karpenter.tf`와 같은 패턴이지만 대상은 kube-system 컨트롤러가 아니라 `system:serviceaccount:default:slash-api`. `slash_api_secret_arns` 변수가 비어있으면(RDS/Valkey 없는 환경) Role 자체를 안 만들도록 `count`로 조건부 처리 — local 환경 호환.
- `environments/dev/eks/main.tf`: `data.terraform_remote_state.database`(신규)로 RDS 마스터 시크릿·Valkey 시크릿 ARN을 읽어와 `slash_api_secret_arns`로 전달. **database가 eks보다 먼저 apply돼 있어야 한다**(기존 순서와 동일, §1).
- `helm/slash-api/templates/deployment.yaml`: `env`에 `envSecrets`(리스트) 렌더링 추가 — 각 이름이 `<release>-secrets`라는 K8s Secret의 동일한 키를 `secretKeyRef`로 참조.
- `helm/slash-api/templates/secretstore.yaml`, `externalsecret.yaml`(신규): `externalSecrets.enabled`가 true일 때만 렌더링(기본 false, 다른 환경/차트 동작에 영향 없음 — `helm template` 기본값으로 렌더링해 SecretStore/ExternalSecret이 안 나오는 것 확인).
- `helm/slash-api/values-dev.yaml`: `env.DB_URL`/`env.VALKEY_HOST`(평문), `externalSecrets.data`(DB_USERNAME/DB_PASSWORD/VALKEY_AUTH_TOKEN, 이슈 #23에 확보된 실제 Secrets Manager ARN 사용)로 실제 값 배선. `VALKEY_AUTH_TOKEN`은 slash-api 앱이 아직 안 읽는 잠정 키 이름(이슈 #23 "문제 1", 앱 코드는 slash-api 팀 몫) — 실제 설정 키가 정해지면 갱신 필요.
- `serviceAccount.roleArn`은 여전히 빈 값 — `environments/dev/eks` apply 후 신규 output `slash_api_role_arn`으로 채워야 함(다음 라운드).
- `helm lint`/`helm template`(기본값·`values-dev.yaml` 둘 다), `terraform validate`(`modules/eks`, `environments/dev/eks`, `-backend=false`)로 검증 완료. 실제 AWS apply·ESO 동작 검증은 다음 라운드(§4 카테고리: 클러스터 Helm 애드온)로 이월.

### 11-2. dev 환경 실제 apply — 상시운영 전환 (2026-08-18)

같은 날 코드 준비(§11-1) 직후 실제로 apply했다. 이번엔 destroy를 예정하지 않는 **상시 운영** 전환이라 §5 절차는 적용 대상이 아니다.

- Terraform: `network`(43)→`cognito`(4)→`database`(RDS+Valkey, 13m29s)→`eks`(21, slash-api IRSA 포함)→`observability`(3)→`llm-runtime`(4, GPU EC2) 순서로 apply. 전부 "N added, 0 changed, 0 destroyed"로 클린 apply.
  - **트러블슈팅**: `database` apply 중 Valkey Secrets Manager 시크릿(`slash/valkey/dev`) 생성이 `InvalidRequestException: already scheduled for deletion`으로 실패 — 8/13 destroy 때 지운 시크릿이 기본 복구 대기 기간(30일) 안에 있어서 같은 이름으로 재생성이 막힘. 사용자 확인 후 `aws secretsmanager delete-secret --force-delete-without-recovery`로 영구 삭제 후 재시도해 해결. **교훈**: dev를 라운드마다 destroy하던 습관 때문에 시크릿 이름이 겹치는 재apply에서 반복될 수 있는 문제 — 상시운영으로 전환했으니 앞으로는 덜 겪겠지만, 혹시 다시 destroy→재apply하게 되면 미리 염두에 둘 것.
  - `network`/`eks`가 새로 만들어지며 subnet ID·SG ID·ACM ARN·RDS 마스터 시크릿 이름·Ollama EC2 사설 IP가 전부 바뀜 — `helm/slash-api/values-dev.yaml`(IRSA roleArn, RDS 시크릿 키, ACM ARN), `helm/slash-llm/values-dev.yaml`(OLLAMA_URL), `karpenter/dev/nodepool.yaml`(subnet/SG selector)을 실제 apply 후 output 값으로 갱신·커밋·push.
- 클러스터 Helm 애드온: ArgoCD(`argocd/README.md`) → ALB Controller → Karpenter 1.10.0(K8s 1.36 호환, `karpenter/README.md`) → metrics-server → **External Secrets Operator**(`external-secrets/README.md`, 신규) 순서로 전부 수동 설치, 전부 정상 기동 확인.
- `argocd/applications-dev/` 3개 apply → 전부 `Synced`. `slash-nlu`/`slash-llm`은 기존 이미지 태그가 남아있어 바로 `Healthy`, `slash-api`는 `image.tag`가 비어 있어 예상대로 `InvalidImageName`(이슈 #11/#23 — CI 워크플로 대기 중).
- **엔드투엔드 검증**: `slash-llm` 파드 → Ollama EC2(새 IP) → 실제 Gemma3 요약 응답 확인(첫 요청은 콜드스타트로 30초 넘게 걸려 타임아웃 났다가 90초로 재시도해 성공 — 이후 요청은 더 빠를 것으로 예상). `slash-nlu` 파드 → `/internal/v1/nlu/analyze` 실제 요청도 정상 응답.
- **ESO 왕복 검증**(이슈 #23/#24 핵심 목표): `slash-api`의 ServiceAccount에 IRSA annotation이 붙은 뒤 `SecretStore`가 `Valid`로 전환 → `ExternalSecret`이 `SecretSynced`로 전환 → `slash-api-secrets` K8s Secret에 `DB_USERNAME`/`DB_PASSWORD`/`VALKEY_AUTH_TOKEN` 키 생성까지 확인(값은 확인하지 않음, 존재만 확인). **처음엔 ArgoCD가 로컬에서 값만 바꾼 values-dev.yaml을 못 봐서(git push 전) IRSA annotation이 안 붙어 `InvalidProviderConfig`로 실패했다** — git push 후 `kubectl patch application ... argocd.argoproj.io/refresh=hard`로 강제 refresh, ExternalSecret은 `force-sync` 어노테이션으로 강제 재동기화해 확인. **교훈**: ArgoCD는 로컬 파일이 아니라 git 원격을 본다 — 로컬에서 값만 바꾸고 push를 깜빡하면 "적용됐는데 왜 안 되지" 착각하기 쉽다.

### 11-3. 다음 라운드로 이월된 작업 (전부 같은 날 처리 완료, §11-4~11-6 참고)

- slash-infra write용 PAT/Deploy key 발급(사용자 액션) + slash-api/nlu/llm 세 저장소 workflow에 tag-bump 스텝 추가(이슈 #11 CI 완료되면 slash-api도 이 경로로 배포됨) → 완료, PAT 발급·PR 3개 merge·실제 dev push로 왕복 검증까지 확인
- AWS Budgets 월 $100 한도, GPU EC2(Ollama) stop/start 정책을 상시운영 기준으로 재검토 → §11-5
- (선택) ArgoCD GitHub webhook 연동 — 이슈 #15 → §11-6, webhook 대신 폴링 주기 단축으로 결론

### 11-4. liveness/readiness probe 연결 (이슈 #25, 같은 날)

slash-llm PR(LikeLionTeam4/slash-llm#5)로 `/health`(liveness)·`/ready`(readiness, Ollama 연결+모델 확인) 분리를 팀원과 리뷰 → 3개 서비스 Helm chart에 실제로 probe 연결.

- slash-api: Spring Boot Actuator가 이미 노출 중인 `/actuator/health/{liveness,readiness}`에 연결(PR #26)
- slash-nlu: 별도 readiness 엔드포인트가 없어 `/health` 하나로 겸용(PR #26), Kiwi 사전 로딩 감안해 `initialDelaySeconds: 20`
- slash-llm: `/ready` merge 확인 후 연결(PR #27) — `LLM_READY_TIMEOUT`(앱 기본 2초)보다 K8s httpGet 기본 timeout(1초)이 짧아서 `timeoutSeconds: 3`으로 여유
- 3개 PR 전부 merge → ArgoCD 자동 반영 → 롤링 업데이트 정상 완료(전 파드 `1/1 Running`, 재시작 0회)까지 확인

### 11-5. GPU EC2 Spot 전환 + 스케줄, Budgets 한도 상향 (이슈 #5, 같은 날)

사용자와 함께 dev 상시운영 기준 비용을 실측 스펙으로 재산정 — EKS/RDS(Multi-AZ)/Valkey/NAT 2개 baseline만 월 ~$380~390, GPU On-demand 상시 가동이면 +~$475(합계 ~$855). 예전 $100 한도는 apply→destroy 라운드 시절 기준값이라 이미 무의미했음.

- **결정**: Ollama EC2를 Spot(월 ~$60~85로 절감) + 평일 09~21시 KST만 가동으로 전환(PR #28). Lambda 없이 EventBridge Scheduler가 EC2 API(`StartInstances`/`StopInstances`)를 직접 호출 — 불필요한 컴포넌트를 안 늘리는 기존 원칙과 같은 방향. `instance_interruption_behavior=stop`이라 AWS가 용량을 회수해도 터미네이트가 아니라 정지, EBS의 모델 설치 상태 보존.
- **트러블슈팅**: Spot 전환은 `aws_instance`의 `instance_market_options`가 ForceNew라 인스턴스 재생성이 필요했는데, 재생성 중 `ap-northeast-2a`에서 g4dn.xlarge `Server.InsufficientInstanceCapacity` 실제 발생(CloudTrail로 재시도 5회 전부 실패 확인, AWS provider가 자동 재시도하느라 겉으로는 "Still creating..."만 계속 찍혀서 원인 파악에 시간이 걸림) — AWS 에러 메시지가 권장한 대로 서브넷을 `ap-northeast-2c`로 고정해서 해결. 재생성으로 사설 IP도 바뀌어(`helm/slash-llm/values-dev.yaml`) 갱신, SSM으로 `gemma3:4b` 재pull 완료 확인 후 반영.
- **Budgets**: 재산정 결과(baseline+GPU Spot·스케줄 ≈ 월 $440~475) 기준 $100 → $500으로 상향(PR #29).
- **번복(같은 날 오후, PR #36)**: 스케줄까지 붙인 뒤 재생성 과정에서 `ap-northeast-2c`마저 같은 `Server.InsufficientInstanceCapacity`를 겪어(재시도 2회 전부 실패) 하루 안에 두 AZ 모두에서 Spot 용량 부족을 확인 — Spot이 주는 추가 절감(월 ~$60~85 vs On-Demand 스케줄 월 ~$170)보다 "업무시간에 못 켜질 수 있다"는 위험이 dev 팀 사용성에 더 크다고 판단해 `use_spot = false`로 On-Demand 재전환. 인스턴스 재교체로 사설 IP도 다시 바뀜(`10.8.11.201` → `10.8.11.172`, `helm/slash-llm/values-dev.yaml` 갱신). **최종 상태: dev의 Ollama EC2는 On-Demand.**

### 11-6. ArgoCD webhook 대신 폴링 주기 단축 (이슈 #15, 같은 날)

즉시 sync를 위한 GitHub webhook 연동은 ArgoCD 서버를 인터넷에 새로 노출해야 해서(서브도메인+ACM+Ingress), 공유 계정 리스크 대비 지금 팀 규모에서 얻는 이득이 크지 않다고 판단해 보류. 대신 `timeout.reconciliation`을 180s(기본) → 60s로 낮춰 지연만 줄임(`helm upgrade`, `argocd/README.md`에 반영) — 새 공개 노출 지점 없이 설정 한 줄로 적용·롤백 가능. `helm upgrade` 후 ArgoCD 전 컴포넌트 정상 재기동, 3개 Application 전부 `Synced`/`Healthy` 유지 확인.

### 11-7. slash-web dev 프론트엔드 착수 (이슈 #31, 같은 날)

백엔드 dev가 실제로 QA 가능해진 뒤(§11-1~11-6)로 미뤄뒀던 착수 조건이 충족돼 바로 진행.

- `environments/dev/frontend`(신규): `environments/local/frontend`와 동일 패턴(S3+CloudFront), `dev.sbsh.cloud`로 apply — 12개 리소스, CloudFront 배포에 시간이 걸림(이번엔 특히 오래 걸려 apply 자체는 20분대, 정상 범위)
- `helm/slash-api/values-dev.yaml`: `ingress.enabled: true` 전환(이미지가 정상 기동 확인된 상태라 이번엔 안전) + `CORS_ALLOWED_ORIGINS` 추가 → ALB 생성 확인 후 `environments/dev/eks/domain.tf`에 alias A레코드 추가(ALB는 Terraform이 모르는 리소스라 DNS/zone ID를 정적 값으로 직접 씀, 기존 ACM cert zone_id와 같은 패턴)
- Cognito 콜백/로그아웃 URL은 `environments/dev/cognito`가 애초에 `dev.sbsh.cloud`를 기본값으로 미리 등록해뒀던 것 발견 — 별도 조치 불필요(선견지명 있는 설계)
- slash-web PR(`deploy-dev.yml`, `deploy-local.yml`과 동일 구조이되 `VITE_API_BASE_URL` 채움 + Cognito 값은 dev 전용이라 저장소 공용 `vars.*` 재사용 안 하고 직접 기입) merge → 실제 배포 확인
- **엔드투엔드 브라우저 검증**: `https://dev.sbsh.cloud` 로딩 → `/login` 클라이언트 라우팅 → "이메일로 계속하기" 클릭 시 실제 Cognito Hosted UI로 리다이렉트, `client_id`/`redirect_uri`/PKCE 파라미터 전부 정확 → 사용자가 직접 로그인까지 성공 확인

### 11-8. local 환경 정리 (같은 날)

dev가 상시운영으로 전환되며 `local/network`(모듈 검증용 기반망)·`local/frontend`(local.sbsh.cloud)·`local/cognito`가 각각 dev의 동급 환경으로 완전히 흡수됨 — 사용자 확인 후 문서화된 순서(§5-1 frontend → §5-4 network → §5-6 cognito, database/eks/observability는 이미 미적용이라 생략)대로 destroy.

- `local/frontend`: CloudFront 비활성화 전파가 이례적으로 오래 걸림(~50분, 보통 15~20분) — AWS SLA 범위 안(최대 90분)이라 별다른 조치 없이 대기, 이후 정상 완료(12개)
- `local/network`: 39개는 정상 삭제, flow-log 버킷만 `BucketNotEmpty`로 실패(§5-4에 이미 문서화된 케이스) — 버전 3301개(오브젝트+삭제 마커) 쌓여있어 `list-object-versions`+`delete-objects`로 배치 비우기 후 재시도해 완료
- `local/cognito`: 4개 정상 삭제(Managed Login branding 삭제에 30초)
- `local/eks`는 원래도 미적용 상태라 손댈 것 없음

최종 확인: `describe-vpcs`/`list-user-pools`로 태그·이름 필터링해 전부 빈 결과, 3개 환경 `terraform state list` 모두 0개.

### 11-9. slash-nlu readinessProbe `/ready` 전환 — 이슈 생성 (이슈 #35, 같은 날)

§11-4(이슈 #25)에서 slash-nlu는 별도 readiness 엔드포인트가 없어 `/health` 하나로 liveness/readiness를 겸했다. 이후 slash-nlu에서 `/health`(프로세스 상태)와 `/ready`(analyzer 준비 상태, 미준비 시 503)를 분리하는 PR이 올라옴 — [LikeLionTeam4/slash-nlu#7](https://github.com/LikeLionTeam4/slash-nlu/pull/7).

- infra 후속 작업을 [이슈 #35](https://github.com/LikeLionTeam4/slash-infra/issues/35)로 생성 — `helm/slash-nlu/templates/deployment.yaml`의 `readinessProbe.httpGet.path`를 `/health` → `/ready`로 변경(`livenessProbe`는 `/health` 유지).
- **블로킹 조건**: `values-dev.yaml`의 `image.tag`가 특정 sha(`sha-d46fa8b81866a0d7f738154591b109dd914583cc`)로 고정돼 있어, PR #7이 merge되어 새 이미지가 빌드되기 전에는 readinessProbe만 먼저 바꿀 수 없다 — 바꾸면 현재 이미지에 없는 `/ready`를 찾다 404로 readiness가 계속 실패한다. 이번엔 §11-4의 slash-llm(PR #27, `/ready` merge 확인 후 연결)과 같은 순서를 그대로 따른 것.
- PR #7에 이슈 #35 링크와 "merge되면 알려달라"는 코멘트만 남기고 대기 — merge 확인 후 probe 변경·`image.tag` 갱신·`helm lint`/`helm template` 검증·dev 배포까지 진행 예정(§11-4와 동일 절차).

**같은 날 이어서 완료**: PR #7이 곧바로 merge됐고(`0b40ee36dfcb`), CD 봇이 `values-dev.yaml`의 `image.tag`를 새 sha로 자동 갱신 — 블로킹 조건이 풀려 나머지 작업을 이어서 진행했다.

- `deployment.yaml`의 `readinessProbe.httpGet.path`를 `/health` → `/ready`로 변경, `helm lint`·`helm template`(기본값/dev/local/prod 전부) 검증 통과 후 커밋·push.
- ArgoCD 기본 폴링 주기(§11-6에서 60s로 단축)를 기다리지 않고 `kubectl patch application slash-nlu -n argocd --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'`로 즉시 반영 확인.
- **검증**: 롤아웃 완료(`kubectl rollout status` 성공) 후 파드 스펙에서 `readinessProbe=/ready`, `livenessProbe=/health` 확인, 파드 안에서 직접 `GET /ready` 호출해 `200 {"status":"UP","analyzerReady":true}` 응답 확인.
- PR #7에 dev 배포 완료 코멘트 작성, 팀원에게 공유.

### 11-10. dev 자유입력 종단 검증 + slash-api/nlu/llm git pull 확인 (같은 날)

§11-9 배포 검증 김에 로컬 `slash-agent`를 dev 모드로 재기동해 실제 PC 에이전트 페어링까지 마친 뒤(설정 > 연동에서 새 코드 발급 → 재페어링 → `READY` 확인), `dev.sbsh.cloud`에서 자유입력 경로를 직접 눌러봤다.

- **`slash-web` 버그 발견·수정**: `/new`에서 지역 없이 "오늘 날씨 어때"처럼 보내면 백엔드가 `NEEDS_CLARIFICATION`으로 응답하는데, 프론트가 이 상태를 종료 상태로 안 봐서 **무한 폴링**되고 백엔드가 준 실제 질문(`question`)도 화면에 안 뜨는 버그를 발견 — `slash-web` 이슈 #32로 등록하고 같은 날 수정(PR #33, `fix/needs-clarification-free-text` → dev merge → CD 자동 배포). `TaskDetail`에 `question`/`correlationId` 필드 추가, `NEEDS_CLARIFICATION`을 별도 phase로 분리해 폴링 중단 + 질문 표시. 답변은 별도 입력 UI 없이 기존 검색창을 고쳐 Enter로 처리 — `slash-api`의 `POST /api/v1/requests`가 `correlationId`를 안 받는(매 요청마다 새로 발급) stateless 구조라 대화 이어가기 자체가 없기 때문. dev 배포 후 실제로 "오늘 날씨 어때" → 질문 표시 → "서울 날씨 어때"로 재입력 → 정상적으로 새 요청이 나가 종료 상태까지 도달하는 것까지 브라우저로 확인.
- **설계 확인**: `slash-api/docs/frontend-api-contract.md`(W1-04 입력창 화면) 상태값 표가 `NEEDS_CLARIFICATION`을 "question을 보여주고 다시 입력받기"로 이미 명시하고 있어, `/chat` 화면으로 전환하는 설계가 아니라 지금 고친 인라인 방식이 계약대로였음을 확인. 나중에 자유 대화형 기능(`GENERAL_CHAT` 등)이 실제로 붙을 때 `/chat/:id`(지금은 `mockThreads.ts` mock 전용)를 진짜 대화 스레드로 재설계할지는 `slash-web` 이슈 #34로 남겨 후속 논의로 미룸.
- **`slash-api`/`slash-nlu`/`slash-llm` 로컬 저장소 git pull 확인**: 세 저장소 모두 origin/dev보다 뒤처져 있어 pull.
  - **`slash-api`**: 두 커밋 새로 확인됨.
    1. **Valkey AUTH/TLS 픽스**(PR #35, `slash-infra` 이슈 #23 연결) — dev 앱이 실제로 **크래시루프**였던 근본 원인 수정. 관리형 Valkey가 `transit_encryption_enabled=true`+AUTH를 요구하는데 앱이 평문 접속을 시도해 TLS 핸드셰이크 타임아웃 → `wsMessageListenerContainer` 초기화 실패 → 프로세스 전체 다운. `application-dev.yml`/`application-demo.yml`에 `password: ${VALKEY_AUTH_TOKEN}` + `ssl.enabled: true` 추가. 확인 시점에 **이미 CD 봇이 자동 배포까지 끝낸 상태**였음(현재 파드 `restarts=0`, `values-dev.yaml` image.tag도 CD 봇이 이미 갱신 — 로컬 clone만 한 커밋 뒤처져 있었음). 커밋 타임스탬프(11:25 KST)가 이번 세션 자유입력 테스트(15시대)보다 훨씬 앞서 있어, 오늘 세션 내내 우리가 테스트한 `/상태`·자유입력·`NEEDS_CLARIFICATION` 전부 이 픽스가 이미 적용된 상태에서 검증한 것으로 확인 — **재검증 불필요**.
    2. **NLU 기본 주소 픽스**(PR #38, 이슈 #20) — `slash.nlu.base-url` 기본값이 `localhost:8000`(slash-llm 포트)으로 잘못 잡혀 있던 걸 `8001`(slash-nlu 포트)로 수정. 커밋 메시지에 "배포는 멀쩡하고 로컬만 깨진다"고 명시 — Helm이 항상 `NLU_BASE_URL=http://slash-nlu`를 명시적으로 주입해 dev 클러스터엔 영향 없는 **로컬 전용 버그**, infra 조치 불필요.
  - **`slash-nlu`/`slash-llm`**: 각각 `/ready` 엔드포인트 merge(#7, #5) — 이미 §11-9/§11-4에서 처리·검증 완료한 것과 동일 커밋, 로컬 clone만 뒤처져 있었을 뿐 새로운 변화 없음.
- **결론**: 이번 git pull로 드러난 변화 중 infra가 추가로 손볼 부분은 없음 — Valkey 픽스는 이미 배포·검증됐고, NLU 포트 픽스는 로컬 전용이라 dev에 영향 없음. 오늘 세션에서 검증한 내용(readinessProbe 전환, 자유입력 NEEDS_CLARIFICATION 수정)도 전부 그대로 유효.

### 11-11. GPU 오토스케일링 필요성 논의 — 이슈 생성 (이슈 #37, 같은 날)

사용자 질문: 요청량이 늘어나면 Ollama GPU 서버도 오토스케일링해야 하는지. 검토 결과 지금 당장은 도입하지 않고, 후속 검토 과제로 [이슈 #37](https://github.com/LikeLionTeam4/slash-infra/issues/37)에 정리해 이월하기로 함.

**보류 판단 근거**:
- 현재 구조(`modules/llm-runtime/main.tf`)는 오토스케일링 그룹이 아니라 EBS 상태(설치된 모델 등)를 보존하는 단독 GPU EC2 + stop/start 스케줄(§11-5) — 오토스케일링을 붙이려면 모델을 매번 새 인스턴스에 새로 받거나 AMI 베이킹/EFS 공유 구조로 재설계해야 해서 지금 설계를 상당 부분 갈아엎어야 함.
- GPU 인스턴스는 부팅+모델 로드에 수 분이 걸림(§11-2에서 콜드스타트 30~90초 실측) — 반응형(reactive) 오토스케일링으로는 어차피 순간 트래픽 급증에 제때 대응하기 어려움.
- 아직 실제 트래픽 병목 근거가 없고, 상향된 $500 예산 한도(§11-5) 안에서 GPU 인스턴스를 추가하는 것은 비용 영향이 큼 — 근거 없이 먼저 늘릴 이유가 없음.

**다음 단계(이슈 #37에 체크리스트로 등록)**: ① Ollama 앞단 요청 큐/동시성 제한 검토 → ② 실사용 GPU 사용률·요청 대기시간 모니터링 체계 마련 → ③ 모니터링으로 병목이 실제 확인되면, 반응형 ASG보다는 예측 가능한 트래픽 패턴에 맞춘 스케줄형 추가 인스턴스 방식 우선 검토 → ④ 오토스케일링 채택 시 모델 배포 방식(AMI 베이킹/EFS 공유 등) 재설계 필요 여부 확인.

## 12. EKS 노드그룹 + RDS 09~21시 스케줄링 (2026-08-19)

사용자 요청: "slash 프로젝트들 모두 9시~21시까지만 운영해도 괜찮을 거 같다 — 그 이후엔 작업 안 함". §11-5에서 Ollama EC2에만 적용해뒀던 평일 09~21시 KST 스케줄을 dev 환경 전체로 확대할 수 있는지 검토.

**범위 결정**: 리소스별로 stop/start 지원 여부가 갈려서 전체를 동일하게 다룰 수 없었다.
- **EKS 범용 노드그룹(EC2)**, **RDS**: 각각 `UpdateNodegroupConfig`(스케일 0)/`StartDBInstance`·`StopDBInstance` API로 stop/start에 준하는 효과를 낼 수 있음 → **적용**.
- **EKS 컨트롤플레인**, **NAT Gateway**, **Valkey(ElastiCache)**, **ALB**: stop 개념 자체가 없어 끄려면 삭제 후 재생성해야 함 — 비용 절감(합쳐서 월 ~$121 추정)보다 매일 밤 재생성하는 리스크(NAT EIP 변경, ALB는 K8s Ingress Controller가 관리해 외부 삭제 시 컨트롤러와 상태 불일치 가능, EKS 컨트롤플레인 재생성은 8/18에 그만둔 destroy/recreate 방식으로 회귀)가 훨씬 커서 **상시 유지로 결정**.
- 비용 추정(Terraform 코드 기준 정가 계산, 실측 아님 — `Project=slash` 비용 배분 태그가 활성화 안 돼 있어 `slash-monthly-cost` 예산의 `ActualSpend`가 계속 $0으로 잡히는 것도 이번에 확인, 별도 후속 필요): EKS 노드그룹 3대(t3.medium) 월 ~$130, RDS Multi-AZ(db.t4g.small) 월 ~$50 — 09~21시 평일만 가동(주 60h/168h ≈ 36%)으로 각각 월 ~$84, ~$32 절감(합계 ~$116/월).

**구현**: `modules/llm-runtime/schedule.tf`와 동일하게 Lambda 없이 EventBridge Scheduler universal target을 직접 쓴다.
- `modules/eks/schedule.tf` — `aws-sdk:eks:updateNodegroupConfig`. 09시엔 `node_desired_size`/`min`/`max`(3/2/4)로 복원, 21시엔 전부 0. `aws_eks_node_group.general`에 `lifecycle { ignore_changes = [scaling_config] }` 추가 — 안 하면 스케줄러가 0으로 바꿔둔 값을 다음 `terraform apply`가 선언값으로 되돌리려는 drift가 매번 감지됨(사이즈를 실제로 바꾸려면 이 lifecycle을 잠깐 지우고 apply해야 하는 트레이드오프를 코드 주석으로 남김).
- `modules/database/schedule.tf` — `aws-sdk:rds:startDBInstance`/`stopDBInstance`. RDS는 Terraform이 인스턴스 실행 상태 자체를 관리하는 속성이 없어 EC2/Ollama 케이스처럼 lifecycle 처리가 불필요.
- 둘 다 `schedule_enabled`(기본 true) 변수로 끌 수 있게 했고, cron/timezone 기본값은 Ollama와 동일(`cron(0 9 ? * MON-FRI *)`/`cron(0 21 ? * MON-FRI *)`, `Asia/Seoul`).

### 12-1. EventBridge Scheduler universal target의 파라미터 casing이 서비스마다 다르다 (2026-08-19)

`environments/dev/eks`, `environments/dev/database` 둘 다 `terraform apply`가 IAM Role/Policy까지는 성공했는데 `aws_scheduler_schedule` 생성이 `ValidationException: ... missing the following field(s)`로 실패했다.

- **EKS**: AWS 공식 API 레퍼런스(`API_UpdateNodegroupConfig.html`)의 요청 바디는 camelCase(`clusterName`, `nodegroupName`, `scalingConfig.desiredSize` 등)라 그대로 썼는데, 실제 필요한 키는 **PascalCase**(`ClusterName`, `NodegroupName`, `ScalingConfig.DesiredSize`)였다.
- **RDS**: 반대로 공식 문서 표기(`DBInstanceIdentifier`, 대문자 DB)를 그대로 썼는데, 실제 필요한 키는 **`DbInstanceIdentifier`**(소문자 b)였다 — Ollama(EC2 `StartInstances`)에서 `InstanceIds`가 그대로 통했던 것과 달리, RDS/EKS는 서비스 내부 모델의 멤버명이 공개 API 문서 표기와 다르게 관리되고 있어서 겪은 불일치.
- **원인**: EventBridge Scheduler의 universal target(`aws-sdk:<service>:<action>`)은 각 서비스의 **공식 REST/Query API 문서 표기가 아니라 AWS SDK 내부 서비스 모델의 멤버명**으로 Input JSON을 검증한다. 이 멤버명은 서비스마다(심지어 같은 서비스 안에서도) 공개 문서 표기와 다를 수 있다 — 이번처럼 EC2는 우연히 일치했지만 EKS(camelCase→PascalCase)/RDS(DB→Db)는 둘 다 달랐다.
- **조치**: 두 모듈 모두 에러 메시지가 알려주는 정확한 필드명으로 수정(`modules/eks/schedule.tf`의 `ClusterName`/`NodegroupName`/`ScalingConfig`, `modules/database/schedule.tf`의 `DbInstanceIdentifier`) 후 재apply, 각각 `2 to add, 0 to change, 0 to destroy`로 정상 완료. `aws scheduler list-schedules`로 4개 스케줄(`slash-eks-node-start/stop-dev`, `slash-rds-start/stop-dev`) 전부 `ENABLED` 확인.
- **교훈**: universal target을 새 서비스에 처음 쓸 때는 공식 API 문서만 믿지 말고, 가능하면 먼저 `plan`이 아니라 실제 `apply`로 한 번 검증하거나(에러 메시지가 정확한 필드명을 알려준다) 그 서비스로 이미 작성된 실제 예제(AWS 공식 유저가이드의 Input 예시 등)를 우선 참고할 것 — REST API 레퍼런스의 바디 표기를 그대로 신뢰하면 안 된다.

**검증 결과**: dev의 EKS 범용 노드그룹·RDS가 평일 09~21시 KST에만 가동되도록 스케줄 적용 완료. 나머지(컨트롤플레인·NAT·Valkey·ALB)는 상시 유지 — 이번 라운드에서 손대지 않음.

### 12-2. 스케줄 밖(09~21시 외 야간)에 수동으로 켜고 끄는 절차 (2026-08-21, §12-3으로 주말 포함 이후 갱신)

**2026-08-21 갱신**: §12-3에서 스케줄을 평일(MON-FRI)에서 매일로 확대해서, 아래 "언제 수동 조치가 필요한가"의 주말 관련 서술은 더 이상 맞지 않는다 — **주말도 이제 09~21시엔 자동으로 켜져 있다.** 수동 조치가 필요한 건 이제 순수하게 "09~21시를 벗어난 시간(매일 21시~다음 날 09시)"뿐이다. 아래 명령어 자체(수동 시작/종료)는 그 경우 여전히 그대로 쓴다.

**언제 수동 조치가 필요한가**:
- **09~21시 안(요일 무관, §12-3 이후)**: 스케줄이 매일 자동으로 켜고 끄므로 **별도 조치 불필요**.
- **21시~09시 사이에 작업하고 싶을 때(요일 무관)**: 스케줄이 그 시간대엔 아예 트리거되지 않으므로 수동으로 켜고, 작업이 끝나면 반드시 수동으로 꺼야 한다.

**수동 시작** (현재 값 기준 — 바뀌면 `environments/dev/eks`/`environments/dev/database`의 스케줄 변수 확인):

```bash
# EKS 노드그룹 (2~3분 소요)
aws eks update-nodegroup-config --cluster-name slash-eks-dev --nodegroup-name slash-eks-general-dev \
  --scaling-config minSize=2,maxSize=4,desiredSize=3

# RDS
aws rds start-db-instance --db-instance-identifier slash-rds-dev

# Ollama(LLM), 필요할 때만
aws ec2 start-instances --instance-ids i-0b4d2b109031a210f
```

NAT/ALB/EKS 컨트롤플레인/Valkey는 상시 유지 대상이라(§12 표) 손댈 필요 없음.

**수동 종료 (작업 끝나면 반드시)**:

```bash
aws eks update-nodegroup-config --cluster-name slash-eks-dev --nodegroup-name slash-eks-general-dev \
  --scaling-config minSize=0,maxSize=1,desiredSize=0

aws rds stop-db-instance --db-instance-identifier slash-rds-dev

aws ec2 stop-instances --instance-ids i-0b4d2b109031a210f
```

**왜 종료를 꼭 수동으로 해야 하는가**: 스케줄이 09~21시(매일)에만 걸려 있어서, 21시 이후에 수동으로 켠 뒤 그대로 두면 다음 09시 전까지 꺼주는 트리거가 없다 — 안 끄면 최소 다음 날 09시까지, 최악의 경우(끄는 걸 계속 깜빡하면) 며칠이고 켜진 채로 과금된다.

### 12-3. 09~21시 스케줄을 평일에서 매일로 확대 (2026-08-21)

**결정**: 팀에서 "주말에도 09~21시는 켜두자"고 정해서, EKS 노드그룹·RDS·Ollama EC2 세 스케줄의 cron을 `MON-FRI`에서 매일로 바꿨다. §12에서 다뤘던 "NAT/ALB/EKS 컨트롤플레인/Valkey는 상시 유지, 나머지 셋만 스케줄 대상"이라는 구조 자체는 그대로 — 스케줄 대상 셋의 **가동 요일**만 넓어진 것.

**구현**: 모듈 기본값(`modules/eks`, `modules/database`, `modules/llm-runtime`의 `variables.tf`)은 `MON-FRI` 그대로 두고, dev 환경 호출부에서만 명시적으로 오버라이드했다 — 모듈 기본값은 "평일만"이 여전히 합리적인 일반 기본값이고, "매일 가동"은 dev 팀의 개별 결정이라 환경 레벨에 남겨야 나중에 이 모듈을 재사용할 다른 환경(local/prod)이 의도치 않게 영향받지 않는다.
- `environments/dev/eks/main.tf`, `environments/dev/database/main.tf`, `environments/dev/llm-runtime/main.tf`에 `schedule_start_cron = "cron(0 9 ? * * *)"` / `schedule_stop_cron = "cron(0 21 ? * * *)"` 추가.
- EventBridge Scheduler cron은 day-of-month·day-of-week 중 하나만 `?`를 쓸 수 있다 — day-of-month는 이미 `?`라 day-of-week에 `*`(매일)를 그대로 쓸 수 있었다.

**적용**: `eks`/`database`는 `terraform apply`로 정상 반영(각각 `2 to change, 0 to destroy`). `llm-runtime`은 계획에 스케줄 cron 2개 외에 **무관한 기존 drift**(`aws_instance.ollama`의 `user_data`)가 같이 잡혀서, 이번 작업 범위가 아니길래 `-target`으로 `aws_scheduler_schedule.ollama_start[0]`/`ollama_stop[0]` 두 개만 지정해서 적용을 시도했다.

**의도와 다르게 동작함 — `-target`이 drift까지 같이 끌고 들어갔다**: 결과는 `2 to change`가 아니라 `0 added, 3 changed, 0 destroyed`. `aws_scheduler_schedule.ollama_start`의 IAM 역할에 붙은 인라인 정책(`aws_iam_role_policy.ollama_scheduler_ec2`)이 `aws_instance.ollama.arn`을 참조하고 있어서, `-target`이 의존성 해석 과정에서 `aws_instance.ollama`까지 실행 대상에 포함시켰고, 한 번 포함된 이상 그 리소스의 **다른 모든 대기 중인 변경사항**(이번 경우 `user_data`)도 같이 적용됐다. CloudTrail로 확인한 실제 순서: `StopInstances`(14:30:36 KST, terraform) → `ModifyInstanceAttribute`(userData, 14:35:19) → `StartInstances`(14:35:20) — `user_data`는 EC2 API가 인스턴스 정지 상태를 요구해서 AWS 프로바이더가 자동으로 stop→수정→start를 수행한 것. 약 5분간 Ollama 다운타임 발생.

**다행히 자가복구됨**: §16에서 만들어둔 `ollama-warmup.service`가 부팅 시 자동 기동돼(`journalctl` 확인: 05:35:31 시작 → 05:36:10 `done_reason: load`) 재기동 후 약 39초 만에 모델이 다시 VRAM에 올라왔다. 게다가 이번에 강제로 적용된 `user_data`는 §16에서 SSM으로 이미 라이브 패치해뒀던 내용과 같아서(코드는 그때 갱신했지만 인스턴스엔 SSM으로만 반영하고 Terraform으로는 반영한 적이 없었음), 이번 일로 그 오래된 known drift가 오히려 해소됐다 — Terraform state와 실제 인스턴스가 이제 일치한다. Private IP(`10.8.11.172`)는 stop/start로는 안 바뀌므로 `helm/slash-llm/values-dev.yaml` 갱신도 불필요했다.

**교훈**: `-target`은 "지정한 리소스만 건드린다"는 보장을 안 해준다 — 참조 관계(특히 IAM 정책의 ARN 참조처럼 값만 갖다 쓰는 것처럼 보이는 관계)를 타고 관련 없어 보이는 리소스까지 실행 대상에 끌려 들어갈 수 있고, 일단 포함되면 그 리소스의 다른 drift까지 통째로 적용된다. 기존 drift가 있는 리소스를 정말로 안 건드리고 싶다면 `-target`보다 먼저 `terraform plan`으로 어떤 리소스가 실행 대상에 포함되는지 확인하거나, 그 리소스에 `lifecycle { ignore_changes = [...] }`를 걸어두는 편이 안전하다.

**비용 영향**: 스케줄 대상 셋의 가동 시간이 주 60h(평일만) → 주 84h(매일)로 늘어난다. §12 정가 계산(730h 기준 EKS 노드그룹 ~$130/월, RDS ~$50/월, Ollama ~$475/월)에 84/730 비율을 적용하면 각각 ~$64/~$26/~$238 — 상시 유지 항목(~$200/월, 변동 없음)까지 합쳐 대략 월 **~$434 → ~$528**, 약 **+$94/월** 증가로 추정.

**검증**: `aws scheduler get-schedule`로 6개 스케줄(`slash-eks-node-start/stop-dev`, `slash-rds-start/stop-dev`, `slash-ollama-start/stop-dev`) 전부 `cron(... ? * * *)`로 바뀐 것 확인.

## 13. CloudWatch 알람 확장(ALB/Valkey) + CloudTrail 문서 정정 (2026-08-19)

사용자 질문 두 가지를 계기로 진행: ① CloudTrail/CloudWatch가 실제로 적용돼 있는지 점검, ② 현재 진행 상황(ALB·ArgoCD 3서비스 상시운영 전환, §11)에 맞춰 CloudWatch 세팅도 맞출 것.

**점검 결과 — 문서-실제 상태 불일치 발견**: `terraform state list`로 재확인해보니 `environments/bootstrap`의 CloudTrail이 실제로는 **적용된 상태**였다. §1 표와 §2 bootstrap 행이 옛날("코드 완료, 미적용") 상태 그대로 남아있었던 것 — 정확히 언제 재apply됐는지 짚어주는 Apply 이력 항목이 없어(§11 상시운영 전환 어딘가에서 같이 됐을 것으로 추정) 확인 시점 기준으로만 §1·§2를 정정했다. CloudTrail은 단일 리전 트레일 + S3 저장까지만 되어 있고, CloudWatch Logs/Athena/GuardDuty 등 로그를 실제로 분석하는 연동은 아직 없음 — 필요해지면 별도 후속.

**CloudWatch 알람 확장**: `modules/observability/rds_alarms.tf` 주석이 "ALB 생기면, GPU 노드그룹 생기면 알람 추가"라고 미뤄뒀던 조건 중 ALB가 이제 충족됐다(§11-7, `api.dev.sbsh.cloud` 연결 완료). RDS와 대칭이 안 맞던 Valkey(ElastiCache) 알람도 이번에 같이 채움. GPU 알람은 여전히 보류(GPU 노드그룹 자체가 없음 — llm-runtime은 별도 EC2 방식, §10).

- **`modules/observability/alb_alarms.tf`(신규)**: `alb_5xx`(`HTTPCode_Target_5XX_Count` 합계 5분당 10건 초과), `alb_target_response_time`(`TargetResponseTime` 평균 2초 초과, 3회 연속). `alb_arn_suffix` 변수가 `null`이면 `count=0`으로 알람을 안 만들게 해서 ALB 없는 환경(local 등)에서도 모듈을 그대로 재사용 가능.
- **`modules/observability/valkey_alarms.tf`(신규)**: `valkey_cpu`(`EngineCPUUtilization` 80% 초과 — `CPUUtilization` 대신 AWS 권고대로 엔진 부하를 더 정확히 반영하는 메트릭 사용), `valkey_memory`(`DatabaseMemoryUsagePercentage` 80% 초과), `valkey_evictions`(`Evictions` 5분당 1건 이상). 마찬가지로 `valkey_cache_cluster_id`가 `null`이면 생성 안 함.
- **ALB 대상을 이름이 아니라 태그로 조회**: AWS Load Balancer Controller가 `group.name`을 안 써서(`helm/slash-api/templates/ingress.yaml`) Ingress마다 전용 ALB가 뜨고 이름이 자동 생성돼 재생성 시 바뀔 수 있다. `environments/dev/observability/main.tf`에서 `data "aws_lb"`를 이름이 아니라 컨트롤러가 항상 붙이는 태그(`elbv2.k8s.aws/cluster`, `ingress.k8s.aws/stack=default/slash-api`)로 조회하도록 함 — 실제 ALB(`aws elbv2 describe-tags`)에서 이 태그값을 먼저 확인한 뒤 반영. **주의**: Ingress가 잠깐이라도 내려가 ALB가 사라진 상태로 apply하면 이 data source가 실패한다.
- **`modules/database/outputs.tf` + `environments/dev/database/outputs.tf`**: `valkey_replication_group_id` output 추가(기존엔 없었음) — Valkey는 단일 노드 replication group이라 실제 `CacheClusterId`는 `<replication_group_id>-001`(`aws elasticache describe-cache-clusters`로 확인 후 반영).

**Apply 순서**: `dev/database`(output만 추가, `0 added/changed/destroyed`) → `dev/observability`(`terraform plan`으로 정확히 `5 to add, 0 to change, 0 to destroy` 확인 후 그 plan 파일로 apply, 기존 RDS 알람 2개는 그대로 유지). `aws cloudwatch describe-alarms`로 7개 전부(RDS 2개는 `OK`, 신규 5개는 데이터 누적 전이라 `INSUFFICIENT_DATA`) 정상 생성 확인.

### 13-1. 후속 이슈 등록 (같은 날)

이번 라운드에서 다루지 않은 관찰 사항 중 후속 검토가 필요한 두 가지를 이슈로 이월했다:

- [이슈 #43](https://github.com/LikeLionTeam4/slash-infra/issues/43) — CloudTrail이 S3에 로그만 쌓고 분석 경로가 없는 상태를 CloudWatch Logs 연동 + 메트릭 필터로 메울지 검토. 공유 계정 특성상 필터가 다른 팀 활동까지 잡을 수 있다는 점을 배경에 명시.
- [이슈 #44](https://github.com/LikeLionTeam4/slash-infra/issues/44) — EKS 컨트롤플레인 로그·컨테이너 로그·CloudWatch Dashboard가 전부 비어있는 상태를 검토. 이슈 #39(장애 대응 시나리오 점검)의 "사후 분석 근거 부재" 문제와 맞닿아 있어 상호 참조.

**llm-runtime EC2(Ollama) 상태 체크 알람은 이슈로 남기지 않기로 판단**: 평일 09~21시 스케줄(§11-5/§12) 밖에서는 정상적으로 꺼져 있는 상태라 상태 체크 알람을 걸면 매일 밤 오탐 처리 로직이 별도로 필요하고, "스케줄 기동 자체가 실패했을 때 감지할 방법이 없다"는 더 근본적인 문제는 이미 이슈 #39의 할 일 목록("EventBridge 09시 자동 기동 실패 대비 런북")이 다루고 있어 중복 이슈를 만들지 않음.

## 14. slash-api values-dev.yaml에 LLM_BASE_URL 배선 (이슈 #42, 2026-08-19)

`slash-api` 담당자(김강찬)가 등록한 [이슈 #42](https://github.com/LikeLionTeam4/slash-infra/issues/42) 대응. `slash-api` PR#42(`TEXT_SUMMARY`를 slash-llm에 연결)에서 `LLM_BASE_URL` 설정이 새로 생겼는데, `helm/slash-api/values-dev.yaml`의 `env`에는 `NLU_BASE_URL`만 있고 `LLM_BASE_URL`이 없었다 — 기본값(`localhost:8000`)으로 배포되면 요약 요청이 `UPSTREAM_UNAVAILABLE`로 조용히 실패하는 상태.

**조치**: `NLU_BASE_URL: "http://slash-nlu"`와 동일 패턴으로 `LLM_BASE_URL: "http://slash-llm"` 추가. `argocd/applications-dev/slash-llm.yaml`이 release 이름을 `slash-llm`으로 쓰고 있어 chart fullname도 `slash-llm`(slash-nlu와 동일 패턴)임을 확인했고, `helm/slash-llm/values.yaml`의 `service.port: 80`→`targetPort: 8000`이라 주입값에는 포트를 안 붙인다.

**후속(이슈 체크리스트 남은 항목)**: slash-api#42 머지·배포 후 실제 `/summary` 왕복 확인은 아직 미완 — infra 쪽 배선만 이번에 반영.

## 15. CloudWatch 대시보드 추가 (이슈 #44, 2026-08-19)

"팀원이 리소스 하나하나 안 보고도 인프라 상태를 한눈에 볼 수 있으면 좋겠다"는 요청 계기로 진행. [이슈 #44](https://github.com/LikeLionTeam4/slash-infra/issues/44) 할 일 목록 중 3번째("대시보드 1개로 RDS/ALB/EKS/Valkey 핵심 지표 시각화")만 처리 — 1·2·4번(로그 수집, 비용 추정)은 범위 밖으로 남겨두고 이슈에 코멘트로 명시했다.

**`modules/observability/dashboard.tf`(신규)**: §13에서 만든 알람 7개(RDS 2 + ALB 2 + Valkey 3)를 그대로 위젯화. 위젯마다 namespace/metric/dimension을 다시 선언하는 대신 `annotations.alarms`로 해당 알람 ARN을 참조하는 방식을 택함 — 알람 쪽 임계값이 바뀌면 대시보드에도 자동 반영되고, 값이 두 군데서 어긋날 일이 없다. ALB/Valkey 위젯은 알람과 마찬가지로 `var.alb_arn_suffix`/`var.valkey_cache_cluster_id`가 `null`이면 생성되지 않는다(local 등에서 모듈 재사용 시 안전).

**EKS는 이번 범위에서 제외**: RDS/ALB/ElastiCache와 달리 EKS는 Container Insights를 켜지 않으면 CloudWatch에 기본 지표를 아예 내보내지 않는다 — 지금 위젯을 만들어도 빈 그래프만 뜬다. Container Insights 도입 여부는 이슈 #44의 1·2번 항목(로그 수집)과 함께 별도로 검토해야 해서 위젯을 보류.

**변수/출력 추가**: `modules/observability/variables.tf`에 `aws_region`(기본 `ap-northeast-2`, 위젯의 `region` 필드용 — 이 모듈은 provider 설정을 갖지 않아 별도로 받아야 함) 추가. `outputs.tf`에 `dashboard_url`(콘솔 바로가기 링크) 추가하고 `environments/dev/observability/outputs.tf`에도 그대로 노출.

**비용**: 계정당 대시보드 3개까지 무료(월 50개 지표 포함)라 이번 1개 추가로는 비용 증가 없음.

**검증 및 apply**: `terraform fmt -recursive` 변경 없음, `terraform validate`(모듈 단독) 통과. `dev/observability`에서 `terraform plan`으로 `1 to add, 0 to change, 0 to destroy` 확인 후 apply — 대시보드 `slash-dashboard-dev` 생성 완료, 위젯 7개(RDS 2 + ALB 2 + Valkey 3) 전부 정상 표시.

`docs/aws-architecture.md` §1-1 구성도와 §10(옵저버빌리티), §13(TODO)도 이번 알람 확장(§13/이슈 #43)·대시보드 추가 반영해 실제 상태와 맞게 갱신 — 기존에 "ALB 5xx 알람은 없다"처럼 남아있던 stale 서술을 정정했다.

## 16. Ollama keep_alive 콜드로드 완화 (이슈 #41, 2026-08-19)

[이슈 #40](https://github.com/LikeLionTeam4/slash-infra/issues/40)에서 실측한 `/summary` 104.47초 지연(콜드로드) → 1.47초(웜) 재현 건의 원인 조치. [이슈 #41](https://github.com/LikeLionTeam4/slash-infra/issues/41)에 팀원(@YeonWoojuice)이 코멘트로 `OLLAMA_KEEP_ALIVE=-1`에 동의하면서 조건 두 가지를 남겼다: (1) `keep_alive`는 Infra 쪽 env var로만 관리하고 `slash-llm` 요청 payload에는 중복으로 넣지 말 것(API 값이 서버 env var보다 우선해서 운영값을 덮어쓸 수 있음), (2) `user_data.sh.tpl`은 최초 부팅 1회만 실행되므로 매일 EC2 stop/start로는 워밍업이 재실행되지 않는 문제를 systemd 서비스로 보완할 것.

**`modules/llm-runtime/user_data.sh.tpl`**: `ollama.service.d/override.conf`에 `Environment="OLLAMA_KEEP_ALIVE=-1"` 추가(§ 기존 `OLLAMA_HOST` 옆). 전용 GPU 인스턴스(`gemma3:4b` 단독)라 VRAM을 나눠 쓸 다른 워크로드가 없어 무기한 유지해도 실질 단점이 없다는 이슈 배경 그대로. 추가로 `ollama-warmup.service`(oneshot, `After=ollama.service`)를 신규 등록해 `systemctl enable`— Ollama가 뜬 뒤 `/api/generate`에 `prompt` 없이 `model`만 담아 보내 모델을 VRAM에 올려두기만 하는 요청을 보낸다. `WantedBy=multi-user.target`이라 매 부팅(=매일 09시 EC2 재기동)마다 실행되어, `user_data`가 1회성이라는 제약을 우회한다.

**`slash-llm` 확인**: `main.py`의 `ask_gemma()`가 `/api/generate`에 보내는 payload(`{"model", "prompt", "stream"}`)에 `keep_alive`가 이미 없는 것을 확인 — 팀원이 우려한 중복 설정 문제는 애초에 없어서 별도 수정 없음.

**dev EC2 반영**: `aws_instance.ollama`는 `user_data_replace_on_change`를 지정하지 않아 기본값(`false`)이라 `terraform apply`만으로는 실행 중인 인스턴스에 반영되지 않는다(stop/start로는 cloud-init이 다시 안 돎, 위 §5-1/§11 설계 그대로). 팀원이 dev를 쓰고 있을 수 있는 시간대라 인스턴스 교체(수 분 다운타임 + private IP 변경으로 `values-dev.yaml` 재배선 필요) 대신 **SSM Run Command(`AWS-RunShellScript`)로 라이브 인스턴스를 직접 패치**했다 — `override.conf`에 `OLLAMA_KEEP_ALIVE=-1` 추가, `ollama-warmup.service` 유닛 생성 후 `systemctl daemon-reload && restart ollama`(중단 수 초). 이슈에 사전 공지 후 진행.

**검증**: `kubectl port-forward svc/slash-llm 18000:80` → `slash-llm/scripts/smoke_dev.py`로 두 케이스 확인.
- 패치 직후(워밍업 서비스가 막 모델을 올린 상태): `/summary` 2.09초
- 5분 유휴 후 재요청: `/summary` **1.63초** — §16 배경의 원인이었던 "5분 후 unload → 재로드 100초+" 문제가 재현되지 않음, `keep_alive=-1` 정상 동작 확인

**추가 검증(2026-08-20, 09시 EventBridge 자동 기동)**: 인스턴스 부팅(00:00:04 UTC) → `ollama-warmup.service` 자동 시작(00:00:17 UTC, 사람 개입 없음) → 모델 로드 완료(`done_reason: load`, 00:00:56 UTC, 부팅 후 52초). `journalctl -u ollama-warmup -b`로 확인. 이후 `smoke_dev.py`로 첫 `/summary` 요청 재확인: **1.80초** — "재기동 직후 첫 요청" 케이스도 콜드로드 없이 정상. 두 케이스(재기동 직후 / 5분 유휴) 모두 확인 완료로 이슈 #41 조치 검증 마무리.

**후속**: dev `LLM_TIMEOUT`을 Backend 60초보다 짧게 조정하는 건 이슈 코멘트에서 @YeonWoojuice가 이 검증 완료 후 진행하기로 한 항목 — infra 쪽에서는 여기까지.

## 17. 파드 레벨 모니터링 현황 확인 + 후속 이슈 등록 (이슈 #47, 2026-08-19)

CloudWatch 대시보드(§15, PR #46) 이후 "RDS/ALB/Valkey는 보이는데 개별 파드는요?"라는 질문 계기로 점검. `kubectl top pod`로 실제 클러스터(`slash-eks-dev`)에 접속해 확인한 결과:

- **`metrics-server`는 이미 설치돼 있었다**(`helm list -A` 확인 — release `metrics-server`, `kube-system`, 2026-08-18 09:25 설치. `aws-load-balancer-controller`/`karpenter`/`external-secrets`와 같은 날 GitOps로 같이 설치됐는데 `docs/aws-architecture.md`에 이 사실이 전혀 반영돼 있지 않았다). `kubectl top pod -n default`로 slash-api/nlu/llm 파드별 CPU/메모리 조회 정상 확인.
- **그럼에도 남는 사각지대**: `metrics-server`는 클러스터 내부용 순간 스냅샷이라 CloudWatch로 안 나가고, 이력도 안 남는다 — 파드가 크래시루프/OOMKilled 나도 사후에 그 시점 리소스 사용량을 볼 방법이 없다(이슈 #39가 다루는 "사후 분석 근거 부재"와 같은 문제).

**조치**: `docs/aws-architecture.md` §5(metrics-server 설치 사실 추가)·§13(TODO에 파드 지표 항목 추가) 갱신. Container Insights vs Prometheus/Grafana 자체 호스팅 중 뭘 선택할지는 비용·운영부담 실측이 필요해 [이슈 #47](https://github.com/LikeLionTeam4/slash-infra/issues/47)로 분리 등록(이슈 #44에 교차 코멘트 남김) — 로그 수집(이슈 #44 1·2번)과 겹치는 부분이 있어 같이 검토.

## 18. 09~21시 스케줄 재점검 + 공유 계정 non-slash 리소스 목록화 (이슈 #53, 2026-08-20)

"09~21시 외엔 절대 사용 안 하기로 했다"는 팀 규칙이 실제로 지켜지고 있는지 점검해달라는 요청으로 시작. `aws ec2 describe-instances`/`describe-db-instances` 등으로 계정 전체를 훑는 과정에서 두 가지를 확인했다.

**① slash 소유 리소스는 이미 정상 — 추가 조치 불필요**: `aws scheduler list-schedules`로 재확인한 결과 `slash-eks-node-start/stop-dev`, `slash-rds-start/stop-dev`, `slash-ollama-start/stop-dev` 6개 스케줄 전부 `ENABLED`, `cron(0 9/21 ? * MON-FRI *)` + `Asia/Seoul`로 §11-5/§12 그대로 적용돼 있었다. EKS 노드그룹은 21시에 `min/max/desired=0`으로 내려가 컨트롤플레인만 남고(파드 전부 종료), 09시에 원상복구된다 — 팀원이 21시 이후 `slash-api` 무응답을 겪은 것도 이 스케줄의 정상 동작이었다.

**② 계정 전체를 훑을 때 `slash-` 접두사 없는 리소스가 섞여 나옴**: `my-ec2-beam0331`(EC2), `my-database-beam`(RDS), `cluster-suis`(EKS), `suis-db`(RDS), `k3-server-suis`(EC2). 이 계정이 여러 수강생·팀이 공유하는 계정이라는 사실 자체는 이미 §4(2026-08-05, GitHub OIDC provider가 `Team1` 소유였던 건)에 기록돼 있었지만, 그때는 "계정당 1개"인 리소스(OIDC provider) 얘기였고 이번처럼 EC2/RDS 같은 일반 리소스가 실제로 몇 개나 섞여 있는지 구체적으로 나열해본 적은 없었다. `aws iam list-users`로 `a-student-03/09/14`, `b-instructor-01/02`, `b-student-01~13`을 확인, `slash-infra` 코드 전체 grep으로 이 리소스명들이 하나도 없음을 확인해 다른 수강생 개인 리소스로 결론 — 건드리지 않음. `docs/resource-ownership.md`에 이 목록과 판별 기준(`slash-` 접두사 + 코드 존재 여부)을 별도 절로 추가해 다음에 계정을 훑는 사람이 같은 조사를 반복하지 않도록 함.

**정정 — Elastic IP 6개는 미사용이 아니었음**: `aws ec2 describe-addresses`에서 `InstanceId`가 전부 `None`이라 처음엔 "미연결 낭비 리소스"로 판단했다. `NetworkInterfaceId`로 재조회해보니 실제로는 NAT Gateway 2개, ALB(`k8s-default-slashapi`) 2개, RDS 퍼블릭 액세스용 ENI 2개에 각각 연결돼 있었다 — EC2에 붙는 EIP만 `InstanceId`로 잡히고 NAT/ALB/RDS ENI에 붙는 EIP는 `InstanceId`가 안 채워지는 게 원인. release 직전에 재확인해서 실제로 실행하진 않았지만, `InstanceId` 필드만 보고 "미연결"이라 단정하면 안 된다는 게 이번 교훈 — 확인하려면 `NetworkInterfaceId`까지 봐야 한다.

**결론**: 이번 라운드는 코드 변경 없음, 문서 정정만 진행(`docs/resource-ownership.md` 신규 절, 본 항목). NAT Gateway·로드밸런서는 "stop" 개념이 없고(삭제/재생성만 가능) 팀 프로젝트 안정성 리스크가 커서 이번에도 스케줄 대상에서 제외하기로 함 — §12 결론과 동일.

**정정(2026-08-24, 이슈 #61) — 위 ①의 "slash 소유 리소스는 이미 정상"은 틀렸다.** 그때 확인한 건 스케줄이 `ENABLED` 상태라는 것뿐이었지, 실제로 호출이 성공했는지는 CloudTrail로 확인하지 않았다. `#61`에서 CloudTrail(`UpdateNodegroupConfig`)을 직접 조회해보니 노드그룹 생성(08-18) 이후 21시 종료 시도가 **한 번도 성공한 적이 없었다** — `ScalingConfig.MaxSize=0`을 EKS API가 `InvalidParameterException`으로 거부하기 때문(`MinSize`/`DesiredSize`는 0 가능, `MaxSize`만 항상 1 이상이어야 하는 AWS 하드 제약). 09시 시작 호출은 `MaxSize`가 0이 아니라 매번 정상 성공했고, 노드 인스턴스 3대의 `LaunchTime`도 스케줄이 아니라 이슈 조사 중 수동 복구(08-21 22:34 KST)한 시각 그대로였다 — 즉 **①에서 "정상 동작"이라고 판단한 21시 무응답은 스케줄이 실제로 작동해서가 아니라 다른 이유였다.** 스케줄 존재 여부(`ENABLED`)만으로 실제 동작을 단정하면 안 된다는 게 이번 교훈 — 실행 이력까지 CloudTrail로 봐야 한다. 수정은 `modules/eks/schedule.tf`(`MaxSize=0`→`1`), 같은 버그를 예시로 갖고 있던 §12-2 수동 명령도 함께 고쳤다.

## 19. NAT Gateway 아웃바운드 장애 — 공유 계정 다른 팀이 실수로 삭제 (이슈 #56, 2026-08-21)

"NAT가 안 되는 것 같다"는 팀원 제보로 점검 시작.

**원인**: `aws ec2 describe-nat-gateways --filter Name=vpc-id,Values=vpc-0cc23d990ea9b2ba9`가 빈 결과 — slash dev VPC에 NAT Gateway가 실제로 0개였다. 라우팅 테이블(`slash-private-app-rt-ap-northeast-2a/2c-dev`)의 `0.0.0.0/0` route는 존재하지 않는 NAT ID(`nat-0605f219892324e9a`, `nat-0f8ebb83909fbf50d`)를 계속 가리키며 `State: blackhole`로 남아 있어, private-app 서브넷(EKS 워크로드) 전체가 아웃바운드 인터넷 연결을 잃은 상태였다.

CloudTrail로 `ResourceName=<natId>` 조회해 타임라인 확정:
- `2026-08-18 08:48` a-student-09가 §11-2 상시운영 재구축 때 생성한 NAT 2개(§2 표에 기록된 그것).
- `2026-08-20 22:24` **b-student-02**(다른 팀 `likelion-cloud6-team3` 소속)가 이 두 NAT를 `DeleteNatGateway`로 삭제. 같은 날 15:33~22:24 사이 b-student-02는 자기 팀 `lion-team3-dev-nat-*`(Owner=`likelion-cloud6-team3`, Project=`lion`) NAT를 반복적으로 생성/삭제하며 apply/destroy 사이클을 돌리고 있었다 — 그 와중에 slash 소유 NAT까지 같이 삭제된 것으로 보인다(의도적 조작 흔적 없음, 계정 공유로 인한 사고로 판단). slash 팀 EIP(`slash-nat-eip-ap-northeast-2a/2c-dev`)는 삭제되지 않고 미연결 상태로 남아 있었다.

**조치**: `environments/dev/network`에서 `terraform plan` → drift 확인(NAT 2개 add, route 2개 update, **0 destroy** — state는 삭제 사실을 몰랐을 뿐 그 외엔 정합). `terraform apply`로 복구: 기존 EIP(`52.79.111.69`, `54.116.233.42`) 그대로 재사용해 새 NAT(`nat-0b04bad708207e27c` AZ-2a, `nat-07e630aaf45bfb021` AZ-2c) 생성, route가 자동으로 새 NAT ID로 갱신됨. 적용 후 `describe-nat-gateways`로 `available` 2개, route `active` 2개 재확인 완료 — 총 장애 지속 시간은 삭제 시점(8/20 22:24)부터 복구(8/21) 기준 약 반나절.

**교훈**: 공유 계정에서는 `slash-` 접두사 리소스도 다른 팀의 실수(잘못된 스코프의 destroy/apply)로부터 완전히 안전하지 않다 — §18에서 다룬 "남의 non-slash 리소스를 건드리지 않기"의 반대 방향 리스크. NAT/EIP처럼 삭제·재생성만 가능한 리소스는 Terraform state가 drift를 정확히 잡아주므로(`0 to destroy`로 안전 확인 가능) 장애 시 우선 `terraform plan`으로 실제 삭제 여부를 판단하고 그대로 `apply`하면 된다. 재발 방지책(예: 공유 계정 삭제 권한 제한, 팀 간 공지)은 인프라 코드 변경 사항이 아니라 계정 운영 정책 문제라 이슈에서 팀에 공유만 하고 별도 후속은 만들지 않음.

**다운스트림 영향 확인 — slash-api 401 로그인 루프**: 같은 시간대 [slash-api#56](https://github.com/LikeLionTeam4/slash-api/issues/56)(유효한 Cognito 토큰인데도 `/api/v1/me` 등이 401)이 별도로 보고돼 있었는데, `kubectl logs`로 원인이 이 NAT 장애였음을 확인했다 — `NimbusJwtDecoder`가 서명 검증용 Cognito JWKS(`cognito-idp.ap-northeast-2.amazonaws.com`, VPC 엔드포인트 없는 퍼블릭 인터넷 경로)를 fetch하지 못해 `ConnectException: Operation timed out`이 반복되고 있었다. NAT 복구 후 파드 안에서 `wget`으로 JWKS 엔드포인트가 `200 OK`로 정상 응답하는 것까지 확인, slash-api#56에 원인·해결 코멘트 남김. private-app 서브넷 아웃바운드 장애는 Ingress 트래픽(ALB→파드)엔 영향이 없어도 파드가 능동적으로 외부(Cognito, 외부 API 등)로 나가는 모든 경로를 끊는다는 점을 이번에 구체적 사례로 확인 — 다음에 "토큰은 멀쩡한데 401"류 증상이 보이면 NAT 상태부터 의심할 것.

## 20. 상시 유지 리소스 삭제 시 SNS 이메일 알림 추가 (§19 후속, 2026-08-21)

§19 사고를 겪고 나서 "이런 게 다시 생기면 바로 알 수 있어야 한다"는 필요로 추가. 조사 중 부수적으로 발견한 것: 기존 CloudWatch 알람(RDS CPU/스토리지, ALB 5xx/레이턴시, Valkey CPU/메모리/eviction, §13/§15)의 SNS 토픽(`slash-alarms-dev`)에 **구독자가 0명**이었다 — `environments/dev/observability/main.tf`에 "구독은 필요할 때 콘솔/CLI로 추가"라는 주석과 함께 의도적으로 비워둔 상태가 지금까지 그대로였던 것. 이번에 같이 메꿨다.

**왜 CloudWatch 알람이 아니라 EventBridge인가**: CloudWatch 알람은 메트릭 기반이라 "리소스가 통째로 사라짐" 자체를 감지하기 어렵다(메트릭이 그냥 없어질 뿐). 대신 이미 켜져 있는 CloudTrail(`slash-trail`)의 관리 이벤트를 EventBridge 기본 버스가 자동으로 실시간 수신하는 것을 이용해, §2에 "상시 유지"로 문서화된 리소스의 `Delete*` API 호출을 곧바로 SNS로 보내는 방식을 택했다.

**`modules/observability/critical_deletion_alarms.tf`(신규)**: 6개 EventBridge 규칙 + 타깃(SNS, `input_transformer`로 사람이 읽을 수 있는 문장으로 가공):
- `DeleteNatGateway`(EC2), `DeleteLoadBalancer`(ELBv2) — **계정 전체 스코프**. NAT/ALB는 재생성될 때마다 ID가 바뀌어 특정 리소스로 미리 필터링할 수 없다. 부트캠프 공유 계정이라 다른 팀이 자기 것을 지워도 같이 울리지만(오탐 감수), §19처럼 "다른 팀이 우리 걸 지웠는데 몰랐다"를 놓치는 비용이 훨씬 크다고 판단해 그대로 둠.
- `DeleteCluster`/`DeleteNodegroup`(EKS), `DeleteUserPool`(Cognito), `DeleteReplicationGroup`(Valkey) — 이름/ID가 고정이라 `requestParameters`로 slash 리소스만 정확히 필터링(각각 `eks_cluster_name`/`cognito_user_pool_id`/`valkey_replication_group_id` 변수, null이면 규칙 자체를 안 만듦).

**SNS 구독 다중화**: `alarm_email`(string) → `alarm_emails`(list(string))로 모듈 변수 변경, `for_each`로 구독 여러 개 생성. `environments/local/observability`는 기존 단일 `alarm_email` 변수를 리스트로 감싸 브리지. `environments/dev/observability`에 팀원 이메일 3개 등록 — `aws sns list-subscriptions-by-topic`으로 전부 `PendingConfirmation` 확인, 각자 메일함에서 Confirm 링크를 눌러야 실제 수신 시작(SNS 이메일 프로토콜 표준 동작).

**검토했다가 보류한 것 — `lifecycle { prevent_destroy = true }`**: NAT Gateway에 걸 수 있는지 검토했으나 (1) 오늘 사고는 애초에 우리 Terraform이 아니라 다른 팀의 AWS API 직접 호출이라 `prevent_destroy`로는 못 막았을 것이고, (2) `modules/network`가 dev(상시 유지)와 local(매 라운드 destroy되는 디스포저블 테스트베드)에서 같이 쓰이는데 `prevent_destroy`는 Terraform이 변수/표현식을 허용하지 않고 리터럴 `true`/`false`만 받아서(직접 `terraform validate`로 확인, `Variables not allowed` 에러) environment별 조건부 적용이 안 된다. 리소스를 이중 정의하는 우회는 route table 참조가 복잡해져서 보류 — 이번 위협엔 EventBridge 알림이 맞는 도구.

**검증**: `terraform plan`(observability, `16 to add, 0 to change, 0 to destroy`) → apply 완료. `aws events list-rules --name-prefix slash-`로 규칙 6개 전부 `ENABLED` 확인.

## 21. mock 이미지 정리 — 세 서비스 전부 실제 Dockerfile/CI 전환 완료 (이슈 #11, 2026-08-24)

`values-local.yaml` 3개(api/nlu/llm)가 이슈 #11이 등록된 뒤로도 계속 `mock-*` 태그를 가리키고 있었다 — dev는 이미 실제 CI 태그(`sha-*`)로 전환됐는데 local만 안 따라간 상태. local이 지금 팀에서 실제로 쓰이고 있진 않지만(작업 우선순위 밖), 그대로 두면 `mock-services/`·ECR lifecycle 규칙까지 계속 안 지워지는 채로 남아 다음에 누가 이 코드를 보면 "아직 Dockerfile이 없나?"로 오해하게 된다.

**조치**:
- `values-local.yaml` 3개의 `image.tag`를 각 서비스 `values-dev.yaml`의 현재 태그로 교체(local 전용 빌드 파이프라인이 없어서 dev에서 검증된 이미지를 그대로 재사용) — api `sha-3d0eadaed6c5`, nlu `sha-86bbfc9b565a`, llm `sha-27d76da2bb1f`
- `mock-services/`(api/nlu/llm mock Dockerfile 3개) 디렉터리 삭제 — 자체 README가 명시한 정리 시점("각 서비스 저장소에 실제 Dockerfile + CI가 생기면 삭제")이 충족됨
- `modules/ecr/main.tf`의 `mock-` 접두어 lifecycle 규칙(3일 후 자동 정리) 삭제 — 더 이상 mock 태그를 push할 데가 없음
- `README.md`/`helm/README.md`/`docs/aws-architecture.md`의 mock-services 관련 서술도 현재 상태에 맞게 정정

**범위 밖으로 남긴 것**: 이슈 #11의 `values-prod.yaml` 항목은 그대로 남아있다 — prod 환경 자체가 아직 미구축이라(§1) 이번 정리와 무관하게 prod 착수 시점에 처리할 일.

**검증**: `values-local.yaml` 3개 외에 `mock-services`·`mock-` 문자열을 참조하는 코드가 더 없는지 전체 grep으로 재확인.

## 22. RDS 관리형 비밀번호 자동 로테이션 시 파드가 옛 비밀번호로 고착되는 현상 확인 (2026-08-24)

이슈 #63(EKS 접근권한) 작업으로 처음 `kubectl` 접근이 열린 직후 `kubectl get pods -A`로 dev 상태를 확인하다가 발견. `slash-api` 파드가 정상(2/2)보다 많은 4개가 떠 있었고, 그중 하나(42분 경과, 12회 재시작)가 계속 `CrashLoopBackOff` 직전 상태였다.

**원인**: `kubectl logs --previous`로 확인한 실제 에러는 `FATAL: password authentication failed for user "slash_admin"`(Flyway 마이그레이션 단계에서 발생, HikariCP 커넥션 획득 실패). RDS가 AWS 관리형 마스터 비밀번호(`manage_master_user_password`)를 쓰고 있어 AWS가 주기적으로 자동 회전시키는데, `aws secretsmanager describe-secret`으로 확인한 결과 같은 날 16:08:28에 로테이션이 있었다. Kubernetes는 Pod의 환경변수(`envSecrets`, `secretKeyRef`)를 컨테이너 재시작 시 다시 읽지 않고 **Pod 생성 시점에 고정**하므로, 로테이션 시점 근처에 이미 떠 있던 파드는 컨테이너가 몇 번을 재시작해도 로테이션 이전 비밀번호로만 계속 접속을 시도해 영원히 실패한다. 같은 시간대 이후 새로 생성된 파드들은 갱신된 비밀번호를 받아 정상 기동했다(`Started SlashApiApplication in 11.685 seconds` 로그로 확인).

**조치**: 코드·설정 변경 불필요 — 문제였던 파드를 확인해보니 조치 전에 이미 사라져 있었다(HPA가 4→2로 스케일다운하며 자연스럽게 정리된 것으로 추정). `slash-api` 2/2 정상 확인.

**참고 — 재발 가능성**: 이번엔 우연히 그 로테이션 타이밍에 떠 있던 파드가 걸려서 드러났을 뿐, **로테이션이 있을 때마다 그 순간 떠 있는 파드는 구조적으로 이 문제에 노출**된다(External Secrets `refreshInterval: 1h`, `helm/slash-api/values-dev.yaml`). 재발 방지가 필요하면 Secret 값 변경 시 파드를 자동 재시작시키는 도구(예: Reloader) 도입이나 `refreshInterval` 단축을 검토할 수 있다 — 이번엔 범위 밖이라 기록만 남긴다. slash-api 저장소에도 같은 내용으로 이슈를 남겨 앱 쪽에서도 같은 증상(로그의 `password authentication failed`)을 다시 조사하지 않도록 했다.

## 23. GPU/클라우드 LLM 인프라 정리 — Ollama EC2·slash-llm 배포 destroy (2026-08-25)

`slash-llm`이 129분째 Not Ready인 걸 발견해 조사하다가(`/ready` 503 반복, `kubectl logs`로 확인), Ollama EC2가 `stopped` 상태인데 **시작/종료 EventBridge 스케줄 자체가 한 번도 apply된 적이 없었다**는 걸 함께 발견했다(`terraform state list` 결과 0개, `modules/llm-runtime/schedule.tf`엔 있는데 실제로 만들어진 적이 없음 — EKS·RDS 스케줄과 달리 이것만 빠져 있었다). 처음엔 "스케줄 버그를 고쳐서 복구"를 계획했으나, 그 전에 "애초에 이 경로가 지금도 쓰이는 게 맞나"를 다시 확인했다.

**제품 방향 재확인 — 이미 폐기된 경로였다**: [slash-docs#3](https://github.com/LikeLionTeam4/slash-docs/issues/3)(2026-08-20)에서 "Slash의 핵심 가치는 클라우드에서 LLM을 직접 제공하는 것이 아니다"로 제품 방향이 바뀌어 있었다. `slash-api` 코드를 직접 검증(`TaskService.resolveExecutionTarget`/`routeToBackend`)한 결과:
- `TEXT_SUMMARY_RUNNER_ENABLED`(기본 `false`, 오늘자 커밋 `b42c2f6`으로 재확인)와 `SUMMARY_ENGINE`(기본 `EXTRACTIVE`, 커밋 `e742675`)이 이중으로 GPU 경로를 막고 있었다
- `helm/slash-api/values-*.yaml` 전체를 grep해도 이 두 값을 오버라이드하는 환경이 하나도 없음 — dev도 예외 아님
- `LlmClient`/`routeToLlm`(GPU 호출 코드)은 삭제되지 않았지만 `SUMMARY_ENGINE=GEMMA`로 명시적으로 바꾸지 않는 한 도달 불가능한 dead code
- `slash-web`/`slash-runner`도 클라우드 LLM을 직접 호출하는 경로가 없음(코드 확인)

즉 **129분 다운타임은 실제 장애가 아니었다** — 이미 아무도 안 쓰는 경로였다. 라이브로도 `slash-api`/`slash-nlu` 둘 다 정상(각 2/2)이고 `NLU_BASE_URL` 배선 확인, 이게 요약 기능을 실제로 처리하고 있음을 재확인했다.

**조치 — 스케줄 복구 대신 자원 자체를 정리**:
- `environments/dev/llm-runtime` `terraform destroy`(`0 to add, 0 to change, 4 to destroy` 확인 후) — EC2·EBS(자동)·IAM Role/Instance Profile 전부 제거. 볼륨엔 재다운로드 가능한 것(OS/Ollama/모델)만 있어 데이터 유실 아님(`user_data.sh.tpl`이 재부팅 시 전부 자동 재설치하도록 이미 짜여 있음)
- `slash-llm` ArgoCD Application을 클러스터에서 직접 삭제(`kubectl delete application`) — `prune: true`인데도 하위 리소스(Deployment/Service/HPA/SA)는 cascade 안 돼서 별도로 수동 정리
- `argocd/applications-dev/slash-llm.yaml`, `argocd/applications/slash-llm.yaml`, `helm/slash-api/values-dev.yaml`의 `LLM_BASE_URL` 제거
- `docs/aws-architecture.md` §5-1에 정리 사실과 사유를 상단에 명시(과거 기록으로 표시, 원문은 보존)

**남겨둔 것**: `modules/llm-runtime`, `helm/slash-llm` 코드 자체는 삭제하지 않았다 — 필요해지면 `terraform apply` 한 번으로 복원 가능(모델 재다운로드 등 user_data가 전부 자동화). Ollama용 보안그룹(`modules/network` 소유)은 비용이 없는 리소스라 이번엔 그대로 둠. `#37`(GPU 오토스케일링 검토)은 대상 자체가 없어져 이번 기회에 닫는 게 맞아 보임 — 별도 확인 후 처리.

**교훈**: "고쳐야 할 버그"로 보였던 게 실은 "이미 안 쓰는 자원이라 아무도 안 챙긴 것"이었다 — 인프라 이상을 발견했을 때 반사적으로 "복구"부터 하지 말고, 그 자원이 지금도 제품에 필요한지부터 코드 레벨로 재확인하는 게 먼저라는 걸 이번에 실제로 겪었다.

## 24. bootstrap state를 로컬 → S3로 이전 (이슈 #66, 2026-08-25)

**문제**: `environments/bootstrap`의 state가 로컬 파일로만 존재해 원 작성자의 컴퓨터 없이는 관리할 수 없었다 — 다른 팀원이 `bootstrap`을 apply/수정하려면 원 작성자에게 `terraform.tfstate`를 직접 받아야 하는 상황.

**조치**: 이미 `bootstrap` 자신이 만든 `slash-tfstate-061039804626` 버킷을 재사용해 backend를 S3로 전환. 원 작성자에게 받은 로컬 state를 그대로 옮겨서 리소스 25개를 재import 없이 승계했다.

```hcl
backend "s3" {
  bucket       = "slash-tfstate-061039804626"
  key          = "bootstrap.tfstate"
  region       = "ap-northeast-2"
  encrypt      = true
  use_lockfile = true
}
```

이전 후 `terraform plan` "No changes" 확인. 같은 PR에서 `enable_log_file_validation = true`(CloudTrail 로그 파일 다이제스트 검증, 무료)도 함께 추가 — S3 Object Lock은 버킷 생성 시점에만 켤 수 있어 지금은 적용 불가(기존 90일치 감사 로그가 있는 버킷을 재생성해야 함), 다음에 버킷을 새로 만들 일이 생기면 그때 같이 검토.

**남은 일**: `environments/dev/eks/domain.tf` 등 `bootstrap` 출력값을 정적 값으로 복사해 쓰던 곳들은 이번 이전과 무관하게 그대로다 — `terraform_remote_state`로 전환하는 건 별도 작업으로 남겨둠(`docs/resource-ownership.md` "왜 이렇게 나뉘었나" 참고). 관련 코드 주석("state가 로컬이라 remote_state 불가")도 이제 기술적으로는 틀린 이유라 갱신이 필요하지만, 이번 범위에서는 처리하지 않음.

## 25. EKS 컨트롤플레인 로그(audit/authenticator) CloudWatch 연동 (이슈 #44/#68, 2026-08-25)

이슈 #44("장애 대응 시 사후 분석 근거 부재")의 로그 수집 항목 중 EKS 컨트롤플레인 로그 부분을 처리. "누가 클러스터 API에 접근했는지" 감사 목적으로 `audit`/`authenticator` 로그만 우선 활성화 — `api`/`controllerManager`/`scheduler`는 지금 필요성이 낮아 비용상 보류.

- `modules/eks/logging.tf`(신규) — 로그 그룹을 EKS보다 먼저 명시적으로 생성. 안 그러면 EKS가 자동 생성하면서 보존기간을 무기한으로 잡아 비용이 계속 쌓이는 함정이 있다.
- `modules/eks/cluster.tf` — `enabled_cluster_log_types = ["audit", "authenticator"]` 추가, `aws_cloudwatch_log_group.eks_cluster`를 `depends_on`에 명시.
- `modules/eks/variables.tf` — `log_retention_days` 변수 추가(기본 30일, prod 등에서 오버라이드 가능).

dev에 적용 후 로그 그룹이 보존기간 30일로 생성된 것, 컨트롤플레인 로깅 상태 전부 실측 확인. `terraform plan` "No changes" 확인.

**남은 일**: 파드/애플리케이션 로그 수집(Fluent Bit vs Container Insights)은 이슈 #44에 계속 남아있음 — `docs/aws-architecture.md` §10 참고.

## 26. 파드 로그(Fluent Bit) CloudWatch 연동 (이슈 #44, 2026-08-27)

이슈 #44의 남은 절반 — 파드 stdout/stderr 수집. `kubectl logs`가 살아있는 파드만 조회 가능해서
파드가 재시작/스케일다운되면 그 시점 로그가 사라지는 문제를 해결. 지표(CPU/메모리,
Container Insights vs Prometheus/Grafana)는 이슈 #47로 여전히 분리해서 미결정 상태로 남김 —
이번 작업 범위 밖.

- `modules/eks/fluent_bit_irsa.tf`(신규) — `slash_api_irsa.tf`/`karpenter.tf`와 같은 패턴의
  IRSA Role. Trust는 `system:serviceaccount:amazon-cloudwatch:fluent-bit`, 정책은
  `logs:CreateLogStream`/`PutLogEvents`/`DescribeLogGroups`/`DescribeLogStreams`만(로그
  그룹은 Terraform이 이미 만들어두므로 `CreateLogGroup`/`PutRetentionPolicy`는 의도적으로 제외).
- `modules/eks/logging.tf` — `aws_cloudwatch_log_group.application`(`/eks/slash-eks-dev/application`,
  `retention_in_days = var.log_retention_days`) 추가. `eks_cluster` 로그 그룹과 같은 이유로
  Fluent Bit보다 먼저 생성해 무기한 보존을 피함.
- `logging/README.md`(신규) — `aws-for-fluent-bit`(공식 `eks-charts`) Helm 설치 문서.
  **주의**: 차트 values.yaml에 CloudWatch 출력 블록이 두 개 있다 — `cloudWatch`(레거시
  `cloudwatch` 플러그인, 기본 `enabled: false`)와 `cloudWatchLogs`(최신 `cloudwatch_logs`
  플러그인, 기본 `enabled: true`). `cloudWatchLogs.*` 키를 써야 한다 — 처음엔 `cloudWatch.*`로
  문서를 썼다가 `helm show values`로 실제 차트를 확인하면서 발견해 정정.

**적용 중 발견한 별개 문제 — 이 머신에 `terraform.tfvars`가 없었다**: `environments/dev/eks`에
로컬 `terraform.tfvars`(gitignore 대상, `team_member_arns`)가 없는 상태로 `terraform plan`을
돌렸더니 Fluent Bit 리소스 3개 추가 외에 **팀원 4명분(`a-student-03`, `a-student-09`,
`b-student-09`, `b-student-10`) 클러스터 접근 권한(`aws_eks_access_entry`/
`aws_eks_access_policy_association`, 인당 2개 = 8개) 전체를 destroy**하려는 계획이 같이
잡혔다 — `team_member_arns` 기본값이 빈 리스트라 tfvars 없이 plan을 돌리면 항상 이 위험이
있다. `aws eks list-access-entries` + `list-associated-access-policies`로 실제
`AmazonEKSClusterAdminPolicy`가 연결된 principal을 조회해 tfvars를 복원한 뒤 재plan으로
"3 to add, 0 to destroy"만 남는 것 확인 후 apply. **교훈**: 이 저장소의 gitignore된 tfvars는
git으로 백업되지 않으므로, 새 머신에서 `dev/eks`를 만질 땐 적용 전 반드시 `terraform plan`으로
destroy 항목이 없는지 먼저 확인할 것 — `terraform.tfvars.example`만 보고 값을 비워두면 안 된다.

**계정 번호 문서 오류도 같이 발견/정정**: `docs/aws-architecture.md`/`karpenter/README.md`에
2026-08-13 계정 재발급(§3, `727646470302`→`061039804626`) 이전 계정 번호가 그대로 남아있던 걸
발견 — 당시 마이그레이션이 `.tf`/`values.yaml` 등 실제 코드는 다 고쳤지만 이 두 문서는
빠뜨렸던 것으로 보인다. 두 문서를 현재 계정 번호로 정정.

적용 후 검증: `kubectl get pods -n amazon-cloudwatch`로 노드 수만큼(3개) DaemonSet Running
확인, `aws logs describe-log-streams`/`get-log-events`로 slash-api/slash-nlu 로그가
실시간으로 들어오는 것 확인. **핵심 검증**: slash-api 파드 하나를 `kubectl delete pod`로
강제 재시작시킨 뒤, `kubectl logs`는 `NotFound`가 되지만 그 파드의 CloudWatch 로그 스트림은
그대로 조회되는 것 확인(46개 이벤트) — 이번 작업이 해결하려던 문제 그대로 해소.

**남은 일**: 1~2일 실사용 트래픽 기준으로 로그 그룹의 `IncomingBytes` 지표를 확인해 실제
수집량을 산정하고 `log_retention_days`(현재 기본 30일) 최종값을 결정할 것 — 비용이 예상보다
크면 7~14일로 낮추는 것도 검토.

**대시보드 위젯 추가(같은 날)**: 위 "남은 일"의 실측을 CLI 없이 확인할 수 있도록
`slash-dashboard-dev`(`modules/observability/dashboard.tf`)에 로그 그룹 `IncomingBytes`
위젯 추가. 기존 위젯은 전부 `annotations.alarms`로 기존 알람을 참조하는 방식인데, 이 위젯은
아직 임계값/알람이 없어 예외적으로 raw metric(`AWS/Logs` 네임스페이스, `LogGroupName`
디멘션)을 직접 선언 — `modules/observability/variables.tf`에 `application_log_group_name`
변수 추가, `environments/dev/observability/main.tf`에서 `eks` 모듈의
`application_log_group_name` output을 전달. `terraform plan`에 무관한 drift(기존 코드에
있었지만 한 번도 apply 안 된 `baegugureview@gmail.com` SNS 알람 구독)가 같이 잡혀서
`-target=module.observability.aws_cloudwatch_dashboard.dev`로 대시보드 리소스만 적용,
`aws cloudwatch get-dashboard`로 위젯 8개(기존 7개 + 신규 1개) 확인. SNS 구독 drift는
이번 범위 밖이라 그대로 보류.

**로그 기반 위젯 2개 추가(같은 날)**: 로그를 tail/Insights 쿼리로만 보면 이해하기 어렵다는
피드백으로, Prometheus/Grafana 같은 별도 스택 없이 지금 있는 CloudWatch 대시보드에만 더
얹었다. `modules/observability/log_metrics.tf`(신규) — 앱 로그 그룹에
`aws_cloudwatch_log_metric_filter`로 `{ $.log = "*ERROR*" }` 패턴을 세는
`Slash/ApplicationLogs.ApplicationErrorCount` 커스텀 메트릭 생성(단순 substring 매칭이라
오탐 가능성 있음 — 지금은 "에러가 튀는 시점"을 대략 잡는 용도로 충분하다고 판단). 대시보드에
"Application Error Count"(시계열 그래프)와 "최근 에러 로그"(Logs Insights 쿼리 결과를 보여주는
`log` 타입 위젯, `query`로 `filter log like /ERROR/`) 2개 추가.

**트러블슈팅**: 로그 관련 위젯 3개(수집량/에러카운트/최근에러로그)를 위젯 하나짜리
리스트 리터럴에 전부 넣었더니 `terraform validate`가 "Inconsistent conditional result
types"로 실패 — 위젯마다 `properties`의 키 구성이 달라서(`metrics` 있는 것 vs `query` 있는
것) Terraform이 하나의 리스트 리터럴 안에서 타입을 통일하지 못했다. `dashboard_widget_alarms`
루프처럼 위젯 하나당 local 하나로 쪼갠 뒤 `concat()`으로 합치는 방식으로 고쳐서 해결 —
concat 인자로 넘기는 리스트끼리는 서로 모양이 달라도 되지만, 리스트 리터럴 하나 안에 섞인
이질적인 object들은 안 된다는 게 이번에 확인한 제약.

적용 후 `aws cloudwatch get-dashboard`로 위젯 10개(기존 7개 + 로그 3개) 확인,
`aws logs describe-metric-filters`로 필터 등록 확인.

## 27. RDS Multi-AZ 장애조치 게임데이 (2026-08-30)

**시나리오**: `docs/resilience-testing.md` §2 ① "RDS Multi-AZ 장애조치" — 프로젝트 마무리 주간을 맞아 실제로 대기 인스턴스 전환이 되는지, 앱이 수동 개입 없이 재연결하는지 처음으로 실행.

**성공 기준**: 앱(slash-api)이 수동 재시작 없이 다시 응답, RDS CPU/연결 알람이 과잉 반응하지 않음.

**타임라인** (UTC 기준, KST는 +9h):
- 04:38:15 — `aws rds reboot-db-instance --db-instance-identifier slash-rds-dev --force-failover` 실행
- 04:38:23 — RDS 이벤트: `Multi-AZ instance failover started`
- 04:38:38 — RDS 이벤트: `DB instance restarted`
- 04:38:57 — slash-api 로그에서 첫 이상 징후: `HikariPool-1 - Connection is not available, request timed out` → `PSQLException: The connection attempt failed` → `SocketTimeoutException: Connect timed out`, 해당 요청은 500 에러로 응답
- 04:39:08 — RDS 이벤트: `Multi-AZ instance failover completed` (주입 시점 기준 총 53초)
- 04:39:24 — `describe-db-instances` 상태 `available` 확인
- 이후 — `kubectl logs -f`로 계속 관찰하려 했으나 로컬 네트워크 연결이 끊겨(`read tcp ...: connection reset by peer`) 스트림이 중간에 끊김. 재시도 없이, 대신 사후에 `kubectl get pods`로 재시작 카운트(변화 없음)와 CloudWatch 알람 상태로 정상화를 간접 확인

**결과**: 성공 기준 충족. `slash-api` 파드 재시작 카운트가 failover 전후로 그대로였음(각각 3회/2회, 둘 다 이 테스트보다 훨씬 이전 시각) — 즉 커넥션 풀이 알아서 재연결했고 파드가 크래시하지 않음. `slash-rds-cpu-dev`/`slash-rds-free-storage-dev` 알람 모두 `OK` 유지. 앱이 에러를 낸 구간은 최소 04:38:57~04:39:08(약 11초) 이상으로 추정되나, 로그 스트림이 끊겨 정확한 마지막 에러 시각(=완전 정상화 시각)은 확인하지 못함.

**발견한 문제**:
1. failover 직후(04:39:24) `describe-db-instances`의 `AvailabilityZone` 필드가 여전히 기존 프라이머리 AZ(`ap-northeast-2c`)로 나와서 "failover가 실제로 안 된 건가?" 혼란이 있었음. 약 1시간 뒤 재조회하니 `AvailabilityZone=ap-northeast-2a`(대기 AZ였던 곳), `SecondaryAvailabilityZone=ap-northeast-2c`로 정상적으로 뒤바뀌어 있었음 — **RDS API의 AZ 메타데이터가 failover 완료 이벤트보다 늦게 갱신되는 지연이 있다는 뜻**. 다음에 같은 테스트를 할 때는 이벤트 로그(`describe-events`)를 우선 신뢰하고, AZ 필드로 성공 여부를 즉시 판단하지 말 것.
2. `kubectl logs -f`를 백그라운드로 띄워 관찰하려 했으나 로컬 네트워크 문제로 스트림이 끊겨 정확한 앱 다운타임(마지막 에러~정상화)을 재지 못함 — 재현 시 `kubectl logs`보다 CloudWatch Logs Insights(Fluent Bit 수집분, `/eks/slash-eks-dev/application`)로 조회하는 게 로컬 네트워크에 안 끊기고 더 안정적일 것.

**다음에 다시 할 때 참고할 것**:
- 앱 컨테이너에 `curl`이 없어(`exec: "curl": executable file not found`) 파드 내부에서 헬스체크를 직접 찌를 수 없었음 — 외부에서 ALB 도메인(`api.dev.sbsh.cloud`)으로 찌르거나 CloudWatch Logs Insights로 확인하는 방식을 기본으로 잡을 것.
- 로컬에서 장시간 로그를 스트리밍하기보다, 테스트 직후 CloudWatch Logs Insights 쿼리로 해당 시간대 로그를 한 번에 뽑는 방식이 더 신뢰성 있음.

## 28. EKS 노드 장애 복구 게임데이 (2026-08-30)

**시나리오**: `docs/resilience-testing.md` §2 ① "EKS 노드 장애 복구" — 노드 하나가 죽었을 때 그 위 파드들이 다른 노드로 재스케줄되는지, `slash-api`가 PodDisruptionBudget 없이도 무중단으로 버티는지 확인.

**성공 기준**: 파드가 다른 노드로 재스케줄, ALB가 그 사이 5xx를 과도하게 내지 않음.

**사전 확인**: `slash-api` 2 replica가 이미 서로 다른 노드(`ip-10-8-11-126`/2c, `ip-10-8-10-29`/2a)에 떠 있었음 — 스케줄러가 우연히 분산시킨 상태(anti-affinity 규칙은 없음). 대상 노드는 `slash-eks-general-dev` 노드그룹(태그 `Project=slash` 확인) 소속 3대 중 `ip-10-8-11-126`으로 선정.

**타임라인** (UTC):
- 07:12:53 — `kubectl cordon` + `kubectl drain --ignore-daemonsets --delete-emptydir-data` 실행
- 07:12:5x — DaemonSet 제외 5개 파드 evict: `argocd-application-controller-0`(StatefulSet, replica 1), `aws-load-balancer-controller`(replica 2 중 1개), `argocd-redis`, `external-secrets-webhook`, `slash-api-...-7mn2w`
- 07:13:26 — 새 `slash-api` 파드가 즉시 다른 노드(`ip-10-8-11-225`)에서 `ContainerCreating` 시작(evict 직후 2초 내 스케줄링됨)
- 07:13:27 — 새 `slash-api` 파드 `Ready`(readiness probe 통과) — drain 시작부터 총 약 34초
- 07:13:27 — `argocd-application-controller-0`도 같은 시점 재기동 완료(약 32초)
- 07:13:42 — `kubectl uncordon`으로 노드 원복

**결과**: 성공 기준 충족. 나머지 1개 replica(`pgjfz`, 다른 노드)가 drain 내내 계속 `Running`이었기 때문에 `slash-api`는 이번 테스트에서 무중단이었음. 재스케줄까지 약 34초.

**발견한 문제**:
1. **이번엔 운이 좋았을 뿐, PodDisruptionBudget이 없다는 근본 문제는 그대로다.** 이번엔 2 replica가 서로 다른 노드에 떠 있어서 무중단이었지만, 만약 두 replica가 우연히 같은 노드에 몰려 있었다면(스케줄러가 그렇게 배치하지 못할 이유가 없음) 그 노드 하나의 장애로 `slash-api` 전체가 몇십 초간 완전히 죽었을 것. `slash-nlu`도 동일한 리스크.
2. `argocd-application-controller`가 StatefulSet replica 1개뿐이라 이 컨트롤러가 뜬 노드가 죽으면 그 순간 ArgoCD sync 자체가 잠깐 멈춘다(이번엔 32초 만에 복구됐지만 이것도 단일 장애점).

**다음에 다시 할 때 참고할 것**:
- `slash-api`/`slash-nlu` Deployment에 `podAntiAffinity`(같은 노드에 2 replica가 몰리지 않도록) 또는 최소한 `PodDisruptionBudget`(`minAvailable: 1`) 추가를 백로그로 남길 것 — 지금 세션 범위 밖이라 코드 변경은 하지 않음.
- 이번엔 `cordon+drain`만 했고 EC2 인스턴스 자체를 종료(`terminate-instances`)하지는 않음 — 노드그룹이 desired=3을 유지하려고 새 인스턴스를 실제로 프로비저닝하는 것까지 보려면 그 방식으로 재시도.

## 29. CloudFront/S3 오리진 차단 게임데이 (2026-08-30)

**시나리오**: `docs/resilience-testing.md` §2 ③ "CloudFront/S3 오리진 차단" — 프론트엔드 오리진(S3, `slash-web-dev-061039804626`)에 CloudFront가 접근 못 하게 되면 사용자에게 어떻게 보이는지, 원복 즉시 정상화되는지 확인.

**성공 기준**: 정책 원복 즉시 정상화. (사전 정의했던 "캐시 hit는 계속 정상 응답" 기준은 이번 요청 경로가 마침 캐시 miss였어서 검증하지 못함 — 아래 발견한 문제 참고.)

**사전 확인**: 버킷 태그 `Project=slash` 확인(같은 계정에 `book-eating-lion-*` 등 다른 팀 버킷이 섞여 있어 이름으로 먼저 필터링 후 태그로 재확인). 기존 버킷 정책을 로컬에 백업.

**타임라인** (UTC):
- 07:14:36 — `aws s3api put-bucket-policy`로 CloudFront OAC principal 대상 `Deny` 문 추가(기존 `Allow` 문 아래에 추가, Deny가 우선 적용)
- 07:14:4x — Chrome(claude-in-chrome)으로 `https://dev.sbsh.cloud/` 접속 → S3 원본 `AccessDenied` XML 그대로 노출됨(CloudFront의 403 → `/index.html` 200 커스텀 에러 매핑도 함께 실패 — 그 매핑이 조회하려는 `/index.html` 자체도 같은 오리진이라 마찬가지로 거부됨)
- 07:15:12 — `aws s3api put-bucket-policy`로 백업해둔 원래 정책(Deny 문 제거)으로 원복
- 07:15:2x — Chrome으로 재접속 → 정상적으로 `/login` 페이지 렌더링 확인

**결과**: 성공 기준 충족 — 정책 원복 후 즉시(수 초 내) 정상화, 별도 무효화(invalidation)나 대기 없이 복구됨. 차단 지속 시간 총 36초.

**발견한 문제**:
1. **오리진이 완전히 막히면 SPA의 404/403→`/index.html` 커스텀 에러 매핑 자체가 무력화된다.** 원래 이 매핑은 "이 파일은 없지만 사이트는 정상"인 상황(SPA 라우팅)을 위한 건데, "오리진 자체가 안 열리는" 상황에서는 매핑이 가리키는 `/index.html`도 못 가져와서 결국 S3의 raw `AccessDenied` XML이 사용자에게 그대로 노출됨. 즉 지금 구조에서 오리진 완전 장애는 아무 안내 페이지 없이 날것의 AWS 에러를 보여주게 된다.
2. 오리진 페일오버(origin group)가 아예 없다는 기존 설계 한계(`docs/aws-architecture.md` §13 TODO)가 이번에 실제로 재현됨 — 대체 오리진이 없어서 정책을 원복하는 것 외에는 복구 수단이 없었음.

**다음에 다시 할 때 참고할 것**:
- 캐시 hit 경로에서는 어떻게 보이는지(계속 정상 서빙되는지) 이번엔 확인 못 함 — 직전에 방문 이력이 있는 정적 자산 경로(예: JS 번들 파일)로 재시도하면 검증 가능.
- 개선 아이디어(이번 세션 범위 밖, 백로그용): CloudFront에 커스텀 에러 응답용 정적 "서비스 점검 중" 오브젝트를 별도 저비용 오리진(예: 같은 버킷 대신 CloudFront Functions로 인라인 HTML 반환)에 둔다면, 오리진 완전 장애 시에도 최소한의 안내는 가능할 것.

## 30. GitHub 장애 대응 리허설 게임데이 (2026-08-30)

**시나리오**: `docs/resilience-testing.md` §2 ④ "GitHub(Actions/저장소) 전체 장애" 런북 — GitHub 자체를 끌 수는 없으니, "ArgoCD가 GitHub을 못 볼 때 수동으로 배포하고, 나중에 GitHub이 복구되면 다시 git 상태로 수렴하는" 절차가 실제로 동작하는지 리허설.

**성공 기준**: (1) auto-sync를 끈 상태에서 수동 이미지 변경이 selfHeal에 의해 되돌려지지 않고 유지됨(= "GitHub 접근 불가 중 수동 배포"가 실제로 가능함을 증명), (2) auto-sync를 다시 켜면 git 추적 버전으로 자동 복구됨(= "GitHub 복구 후 정상화"가 자동으로 됨을 증명).

**타임라인** (UTC):
- 07:16:28 — `kubectl patch application slash-api -n argocd --type merge -p '{"spec":{"syncPolicy":{"automated":null}}}'`로 auto-sync 해제(GitHub 접근 불가 시뮬레이션). argocd CLI가 로컬에 없어 Application CR을 kubectl로 직접 patch하는 방식 사용 — 첫 시도(`{"syncPolicy":{}}`)는 JSON merge patch가 기존 필드를 안 지워서 실패, `automated` 필드를 명시적으로 `null`로 지정하고서야 제거됨
- 07:17:06 — `kubectl set image deployment/slash-api slash-api=<ecr>:sha-bfc52f047376...`(하루 전 이미지 태그)로 수동 배포 — "GitHub Actions 없이 이미 ECR에 있는 이미지로 긴급 배포"를 시뮬레이션
- 07:17:2x — 롤아웃 완료, 이미지가 수동 지정한 옛 태그로 유지됨, ArgoCD `sync.status`가 `OutOfSync`로 전환(자동 되돌림 없음)
- 07:18:15 — `syncPolicy.automated`를 `{"prune":true,"selfHeal":true}`로 복원(GitHub 복구 시뮬레이션)
- 07:18:22 — selfHeal이 git에 기록된 원래 태그(`sha-2f05efc3ee265550287cc0a8c77ccfdc337819bd`)로 이미지를 자동으로 되돌림, `sync.status`가 다시 `Synced` — 복원 지시 후 약 7초
- 07:18:2x — `kubectl rollout status`로 최종 롤아웃 정상 완료, `slash-api` 2/2 Ready 확인(롤아웃 도중 잠깐 나타났던 다른 이름의 Error 파드는 확인 시점엔 이미 사라지고 없었음 — 오래된 다른 ReplicaSet 잔재로 추정, 이번 테스트와 무관해 보이지만 원인은 특정하지 못함)

**결과**: 성공 기준 모두 충족. 수동 배포 유지(약 1분 유지 후 의도적으로 되돌림) + auto-sync 복원 후 약 7초 만에 git 상태로 자동 수렴.

**발견한 문제**: 없음 — 런북이 문서 그대로 동작함을 확인. 다만 argocd CLI가 로컬 개발 환경에 없어서 `kubectl patch`로 우회해야 했다는 점은 실제 장애 상황에서도 동일한 제약이 될 수 있음(argocd CLI 또는 UI 접근성 확보 필요).

**다음에 다시 할 때 참고할 것**:
- `syncPolicy.automated`를 지우려면 `{"automated":null}`처럼 값 자체를 `null`로 줘야 함 — 빈 객체 `{}`로는 안 지워짐(JSON merge patch의 일반적인 동작이지만 처음엔 헷갈림).
- argocd CLI 설치/로그인 절차를 `docs/`에 미리 남겨두면 다음 리허설이 더 빠를 것.

## 31. Secrets 유출 대응 리허설 게임데이 (2026-08-30)

**시나리오**: `docs/resilience-testing.md` §2 ② "Secrets 유출 대응(수동 로테이션)" — Valkey AUTH 토큰이 유출됐다고 가정하고, 지금 바로 무효화(재발급) → 파드가 새 값으로 재연결까지 실제로 되는지 확인. §22(RDS 관리형 비밀번호 로테이션 시 파드가 옛 비밀번호로 고착되던 문제)와 같은 근본 원인(파드 env는 생성 시점에 고정)이 Valkey에도 있는지 같이 검증.

**성공 기준**: 옛 토큰은 더 이상 유효하지 않음(유출 무효화 확인), 새 토큰으로 파드가 정상 재연결(크래시 루프 없이).

**타임라인** (UTC):
- 07:20:41 — `terraform plan -replace=module.database.random_password.valkey_auth`로 영향 범위 먼저 확인(Valkey 관련 리소스 3개만 — `random_password`, `aws_secretsmanager_secret_version.valkey`, `aws_elasticache_replication_group.main`의 `auth_token`. 무관한 drift 없음)
- 07:20:41~07:21:07 — `terraform apply -replace=...`로 새 토큰 강제 생성 → ElastiCache `auth_token` 인플레이스 수정 21초 소요 → Secrets Manager(`slash/valkey/dev`) 새 버전 반영. **ElastiCache가 별도의 2단계 ROTATE/SET 절차 없이 단일 `apply`로 즉시 반영됨** — RDS 관리형 로테이션보다 훨씬 단순
- 07:22:12 — `kubectl annotate externalsecret slash-api-secrets force-sync=$(date +%s) --overwrite`로 강제 동기화(기본 `refreshInterval: 1h` 대기 안 함), 1초 만에 `status.refreshTime` 갱신 확인 → k8s Secret의 `VALKEY_AUTH_TOKEN` 값이 새 토큰으로 바뀜
- 로테이션 직후 3분간 `kubectl logs`로 관찰했으나 **이미 떠 있던 파드에서 Valkey 관련 에러가 전혀 발생하지 않음** — RDS(§22)와 달리 기존 커넥션이 즉시 끊기지 않는 것으로 보임(§22와 원인은 같아도 증상이 다르게 나타남 — 아래 "발견한 문제" 참고)
- 07:22:49 — `kubectl rollout restart deployment/slash-api` 실행(§22의 교훈에 따라 로테이션 후 무조건 재시작하는 절차를 이번에 리허설)
- 07:22:49 이후 — 새 파드 2개 모두 `1/1 Running`, **재시작 카운트 0**으로 정상 기동(크래시 루프 재현 안 됨)
- 리허설 마지막 — 새 토큰으로 임시 파드(`redis-cli` 이미지, `kubectl run --rm`)를 띄워 `redis-cli --tls -a <새 토큰> ping` 실행 → `PONG` 응답으로 새 토큰이 실제로 유효함을 직접 확인

**결과**: 성공 기준 중 "새 토큰으로 정상 재연결"은 직접 확인(크래시 없이 `PONG`까지 검증). "옛 토큰 무효화"는 **직접 검증하지 못함** — 로테이션 전에 옛 토큰 값을 따로 저장해두지 않아 로테이션 후 A/B 테스트를 할 수 없었음. 다만 ElastiCache의 `auth_token`은 (ROTATE 단계를 안 거쳤으므로) 값 자체가 완전히 교체되는 단일 값이라 옛 토큰은 구조적으로 더 이상 유효하지 않을 것으로 판단.

> **정정 (§37, 2026-08-31)**: 위 마지막 문장은 **틀렸다.** 실제로 재검증해보니 `auth_token_update_strategy` 기본값이 `ROTATE`라서 옛 토큰이 새 토큰과 함께 당분간 계속 유효했다 — "ROTATE 단계를 안 거쳤으므로"라는 추측 자체가 잘못된 전제였음. §37에서 `auth_token_update_strategy = "SET"`으로 코드에 명시해 실제로 즉시 무효화되도록 고쳤다. 아래 §31 내용을 볼 때 이 정정을 함께 참고할 것.

**발견한 문제**:
1. **Valkey AUTH 로테이션은 RDS 관리형 비밀번호 로테이션(§22)과 증상이 다르다.** RDS는 로테이션 즉시 기존 커넥션/재연결 시도가 옛 비밀번호로 실패해 CrashLoopBackOff까지 갔지만, Valkey는 로테이션 후 3분 넘게 기존 파드에서 에러가 전혀 안 났다 — 아마 Lettuce(Redis 클라이언트)가 이미 맺은 커넥션을 계속 재사용하고 있어서였을 것. 즉 "로테이션했는데 아무 에러도 안 보인다"는 상태가 오히려 **더 위험할 수 있다** — 유출된 옛 세션이 계속 살아있을 가능성을 의미하기 때문. 진짜 유출 대응이라면 로테이션 직후 반드시 `rollout restart`까지 실행해서 기존 커넥션을 강제로 끊어야 한다는 게 이번에 확인한 핵심 교훈.
2. 로테이션 전에 옛 토큰 값을 기록해두지 않아 "무효화 확인"을 직접 못 했음 — 재현 가치가 있는 실수라 기록.

**다음에 다시 할 때 참고할 것**:
- 이번 절차(terraform apply -replace → force-sync → rollout restart → 새 토큰 ping 검증)를 그대로 `docs/resilience-testing.md`의 표준 절차로 굳혀도 될 만큼 깔끔하게 됐음.
- 다음엔 로테이션 직전에 `aws secretsmanager get-secret-value`로 옛 토큰을 임시로 저장해뒀다가, 로테이션 후 그 옛 토큰으로 `redis-cli ping`을 시도해 `NOAUTH`/`WRONGPASS`로 거절되는 것까지 확인할 것.
- Reloader 같은 자동 재시작 도구는 여전히 미도입 상태 — 이번에도 `rollout restart`를 수동으로 실행해야 했음. §22와 함께 여전히 남은 숙제.

## 32. 부하테스트 + Container Insights 게임데이 (2026-08-31)

**시나리오**: `docs/resilience-testing.md` §2 ① "부하테스트 / HPA 오토스케일링 검증" — `slash-api`에 점증 부하를 걸어 HPA(CPU 70%, min2/max4)가 실제로 스케일아웃하는지, ALB 5xx가 발생하지 않는지 확인. 관측 채널 중 하나로 Container Insights(`amazon-cloudwatch-observability` addon)를 이번에 한해 임시 설치.

**성공 기준**: HPA가 CPU 70% 기준으로 실제 스케일아웃, ALB 5xx 발생 안 함, 부하 종료 후 스케일다운까지 정상 복귀.

**사전 확인**: 인증 없이 접근 가능한 엔드포인트는 `/actuator/health/readiness`, `/actuator/health/liveness`뿐(그 외 API는 `AUTH_REQUIRED` 401) — 이 저장소(slash-infra)에는 앱 소스가 없어 인증 우회/테스트 계정 발급이 불가능했으므로, 부하는 헬스체크 엔드포인트에만 걸었다는 한계를 미리 기록해둔다. 로컬에 `k6`/`hey` 미설치, `ab`(Apache Bench)는 설치돼 있어 이를 사용.

**타임라인** (UTC):
- 01:31:57 — 사전 상태 확인: HPA `cpu: 1%/70%`, replica 2/2, ALB/타겟그룹 식별, Container Insights addon은 전날(08-30) 이미 설치돼 `ACTIVE` 상태였음을 재확인
- 01:32:06 — `kubectl get hpa -w`, `kubectl top pods`(10초 간격) 백그라운드 관측 시작
- 01:32:36 — `ab -n 500000 -c 300 -t 180 https://api.dev.sbsh.cloud/actuator/health/readiness` 실행(동시성 300, 최대 180초)
- 01:33:01~01:34:29 — HPA 관측값이 `cpu: 4%/70%` → **`69%/70%`** → `59%/70%` → **`76%/70%`** → `41%/70%`로 급등 후 하강. 같은 구간 `kubectl top pods` 값도 파드당 4m→137~201m(요청값 250m 대비)으로 동반 상승해 교차 확인됨
- 01:35:37 — `ab` 종료: 총 30,529 요청 완료, **실패 0건**, 평균 169.56 req/s, 최대 응답시간 5.8s(동시성 300 하에서의 커넥션 대기 포함)
- 01:35:37 이후 — HPA `cpu`가 20%대까지 하강하는 동안에도 **replica는 2/2에서 전혀 변하지 않음**(스케일아웃 자체가 발생하지 않음)
- 사후 조회 — ALB(`k8s-default-slashapi-da025791f3`) CloudWatch 지표: `HTTPCode_Target_5XX_Count` 전 구간 **0**, `RequestCount`는 01:33분 구간 10,883/분까지 상승, `TargetResponseTime` 평균은 부하 최대 구간에도 약 21~30ms로 낮게 유지

**결과**: 부분 충족. "ALB 5xx 없음"은 충족(0건). 하지만 **"CPU 70% 기준 스케일아웃"은 CPU가 76%까지 두 차례 임계값을 초과했음에도 실제로는 트리거되지 않아 미충족** — 이번 게임데이의 핵심 발견.

**발견한 문제**:
1. **HPA가 CPU 70% 초과를 감지했음에도 스케일아웃하지 않음.** 임계값을 넘긴 구간이 약 90초(HPA 동기화 주기 15초 기준 6회 정도)로 상대적으로 짧았고, `ab`가 정확히 180초 후 종료되며 부하가 급격히 빠졌다 — HPA의 스케일업 결정과 실제 파드 스케줄링 사이의 지연(수십 초) 안에 부하가 이미 꺾여버렸을 가능성이 높다. **다음 부하테스트에서는 CPU 70%+ 상태를 최소 3~5분 이상 유지**해서 스케일아웃이 실제로 트리거되는지 별도로 재검증 필요 — 이번 결과만으로 "우리 시스템의 오토스케일링이 작동하지 않는다"고 단정할 수는 없지만, "작동한다"고 확인도 못 했다는 뜻이므로 그대로 열어둔다.
2. **Container Insights addon이 `ACTIVE` 상태였지만 지표가 CloudWatch에 하나도 올라가지 않고 있었다.** `cloudwatch-agent` 파드 로그에서 `AccessDeniedException: ... slash-eks-node-dev ... not authorized to perform: logs:PutLogEvents`를 확인 — 노드 IAM 역할에 `CloudWatchAgentServerPolicy`(또는 최소 `logs:PutLogEvents`)가 없어 addon 설치만으로는 동작하지 않음. 같은 계정의 다른 팀 클러스터(`lion-team3-*`)는 정상적으로 지표가 올라오고 있어 계정/네임스페이스 문제가 아니라 우리 노드 역할만의 IAM 갭임을 확인. 이 부하테스트 자체는 `kubectl top`(metrics-server) + HPA 컨트롤러 + ALB CloudWatch 지표로 대체 관측해 완료했다. 상세 내용은 이슈 [#47](https://github.com/LikeLionTeam4/slash-infra/issues/47)에 코멘트로 남김 — 옵션 1(Container Insights)을 실제 채택할 경우 이 IAM 갭을 먼저 메워야 함.
3. 인증 없이 접근 가능한 엔드포인트가 헬스체크뿐이라 실제 비즈니스 트래픽 패턴(로그인 필요 API)에 대한 부하테스트는 이번에 하지 못했다는 한계.

**다음에 다시 할 때 참고할 것**:
- 부하 지속시간을 5분 이상으로 늘려 실제 스케일아웃 트리거 여부를 재검증할 것 — 이번 결과는 "미확인"이지 "실패"가 아님을 §5 인덱스에도 그대로 반영.
- Container Insights를 다시 켜기 전에 노드 역할에 `CloudWatchAgentServerPolicy`부터 붙일 것(이슈 #47).
- 다음 부하테스트는 인증이 필요한 실제 API 엔드포인트까지 포함하려면 테스트 전용 계정/토큰 발급 절차를 먼저 준비할 것.
- 테스트 종료 후 `aws eks delete-addon --cluster-name slash-eks-dev --addon-name amazon-cloudwatch-observability` 실행, `DELETING` 상태 확인함(완전 삭제까지는 시간이 더 걸릴 수 있어 다음 세션에서 최종 상태 재확인 권장).

## 33. 부하테스트 재검증 — 장시간 부하 (2026-08-31)

**시나리오**: §32에서 미확인으로 남긴 "HPA가 CPU 70% 기준으로 실제 스케일아웃하는지"를 재검증. §32는 부하가 90초 만에 꺼지면서 HPA 판단 타이밍을 놓쳤을 가능성이 있었으므로, 이번엔 부하 지속시간을 최대 7분(420초)까지 늘려서 재시도. 인프라 변경 없이(Container Insights 재설치 안 함) `kubectl top`/HPA/ALB 지표만으로 관측.

**성공 기준**: §32와 동일 — CPU 70% 이상이 충분히 지속되면 HPA가 replica를 늘리는지 확인(스케일아웃이 안 일어난다면 그 이유가 "임계값 미도달"인지 "HPA 자체 문제"인지 구분).

**타임라인** (UTC):
- 01:51:01 — 사전 상태 확인: HPA `cpu: 1%/70%`, replica 2/2. `kubectl get hpa -w`(HPA), `kubectl top pods` 15초 간격(CPU) 백그라운드 관측 시작
- 01:51:06 — `ab -n 1000000 -c 300 -t 420 https://api.dev.sbsh.cloud/actuator/health/readiness` 실행(최대 7분, 최대 100만 요청 조건)
- 01:51:33~01:55:14 — `kubectl top pods` 관측: 파드당 CPU가 초반 3~4m → 약 30초 만에 48~74m으로 상승한 뒤 **그 수준(파드당 57~75m, 요청값 250m 대비 약 23~30%)에서 안정적으로 유지**됨. HPA `cpu` 값도 이 구간 내내 **24~29%/70%**로 안정 — 70%에 전혀 도달하지 못함
- 01:55:09 — `ab`가 **예상과 다르게 조기 종료**: 지정한 `-t 420`(420초)/`-n 1000000`에 한참 못 미친 **242초 경과 / 50,000 요청 완료** 시점에 중단됨. 실패 요청은 0건으로 집계됐지만 `Connect` 시간 통계에 `min -793ms`라는 물리적으로 불가능한 음수 값이 나타남 — 로컬 macOS 클라이언트가 테스트 도중 절전/타임점프 등을 겪어 `ab`의 경과시간 계산이 깨졌을 가능성이 높음(서버 쪽 문제 아님). `ulimit -n` 확인 결과 1,048,576으로 파일 디스크립터 고갈은 원인에서 배제됨
- 01:55:30 — 관측 종료, HPA `cpu: 1%/70%`로 원상태 복귀, replica는 시종일관 2/2로 변화 없음

**결과**: **HPA는 정상 동작한 것으로 결론.** §32에서 관측했던 69~76% 스파이크는 재현되지 않았고, 같은 동시성(300)의 지속 부하에서 실제 정상상태 CPU는 24~29%로 안정적이었다 — 즉 §32의 스파이크는 사실상 순간적인 워밍업(TLS 핸드셔킹/커넥션 풀 초기화 등) 아티팩트였을 가능성이 높고, **지속적인(steady-state) 부하는 애초에 70% 임계값 근처에도 못 미쳤다.** 따라서 "HPA가 스케일아웃을 안 한 것"은 HPA의 결함이 아니라 **이 테스트 조건(동시성 300, 헬스체크 엔드포인트)이 실제로 스케일아웃을 유발할 만한 부하가 아니었기 때문**이라는 게 이번에 얻은 결론이다. §32의 "미확인"을 "HPA 정상, 이번 부하 강도가 부족했을 뿐"로 갱신한다.

**발견한 문제**:
1. 로컬 macOS에서 실행한 장시간(4분 이상) `ab` 세션이 중간에 클라이언트 자체의 이상(음수 커넥션 시간, 지정 시간의 절반만 채우고 조기 종료)을 보였다 — 노트북 절전/화면잠금 등 로컬 환경 요인으로 추정, 서버 측 이상 징후는 전혀 없었음(HPA/CPU 관측치는 끊김 없이 정상적으로 계속 수집됨). **장시간 부하테스트는 로컬 노트북이 아니라 별도 EC2/러너에서 실행해야 신뢰할 수 있다**는 게 이번에 얻은 교훈.
2. 동시성 300 × 헬스체크 엔드포인트로는 CPU 요청값(250m)의 30%도 못 채운다 — 실제로 70%까지 밀어붙이려면 동시성을 훨씬 높이거나(1000+), 헬스체크보다 무거운 실제 비즈니스 엔드포인트가 필요함. 이 저장소(slash-infra)엔 앱 소스가 없어 더 무거운 엔드포인트를 새로 만들 수는 없으므로, 순수 인프라 관점에서는 "HPA 설정 자체는 정상"이라는 확인까지가 이번 범위의 한계.

**다음에 다시 할 때 참고할 것**:
- HPA 스케일아웃을 실제로 트리거해보고 싶다면 동시성을 1000 이상으로 올리거나, 인증 우회용 테스트 계정으로 실제 비즈니스 엔드포인트에 부하를 걸 것.
- 4분을 넘는 부하테스트는 로컬 노트북 대신 EC2(예: 임시 `t3.micro`)나 CI 러너에서 실행해 클라이언트 측 이상 변수를 없앨 것.
- §32의 "부분 충족" 결론은 이번 §33으로 "HPA 정상, 부하 강도 부족"으로 업데이트됨 — §5 인덱스도 함께 갱신.

## 34. Container Insights IAM 갭 수정 검증 (2026-08-31)

**시나리오**: §32에서 발견한 문제 — `amazon-cloudwatch-observability` addon이 `ACTIVE`인데도 노드 IAM 역할(`slash-eks-node-dev`)에 `logs:PutLogEvents` 권한이 없어 지표가 전혀 안 올라가던 것 — 을 이슈 [#47](https://github.com/LikeLionTeam4/slash-infra/issues/47)에 기록만 해두고 넘어갔는데, 실제로 정책을 붙이면 해결되는지 검증. IAM 정책 부착/해제는 "보안 설정 변경"에 해당해 에이전트가 직접 실행할 수 없어 사용자가 직접 명령을 실행함.

**성공 기준**: `CloudWatchAgentServerPolicy`를 노드 역할에 붙이고 addon을 재설치하면, `cloudwatch-agent` 파드 로그에 `AccessDeniedException`이 재발하지 않고 CloudWatch `ContainerInsights` 네임스페이스에 실제 지표(`pod_cpu_utilization` 등)가 올라오는지 확인.

**타임라인** (UTC):
- 01:59:xx — 사용자가 직접 `aws iam attach-role-policy --role-name slash-eks-node-dev --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy` 실행, 부착 확인
- 01:59:57 — `aws eks create-addon --cluster-name slash-eks-dev --addon-name amazon-cloudwatch-observability` 재설치
- 02:00:37 — addon `ACTIVE`, `cloudwatch-agent`/`fluent-bit`/`amazon-cloudwatch-observability-controller-manager` 파드 전부 새로 기동, `1/1 Running`
- 02:02:xx — `kubectl logs`로 새 `cloudwatch-agent` 파드 확인 — **`AccessDeniedException` 재발 없음**
- 02:00:37~02:02:xx — `aws cloudwatch list-metrics --namespace ContainerInsights --dimensions Name=ClusterName,Value=slash-eks-dev`를 20초 간격으로 폴링(Monitor 사용), **약 2분(6회 폴링) 만에 26개 지표 등장** — §32 때는 94분이 지나도 0개였던 것과 대조적
- 02:02:00 — `get-metric-statistics`로 `slash-api` 파드의 `pod_cpu_utilization` 실측값 확인: 평균 0.139%, 최대 0.153% — 같은 시각 idle 상태의 `kubectl top`(파드당 3~5m/2000m 노드 용량 기준)과 정확히 일치

**결과**: 성공 기준 완전 충족. IAM 갭이 유일한 원인이었고, 정책 하나만 붙이면 addon이 완전히 정상 동작함을 실측으로 확인.

**발견한 문제**: 없음 — 가설이 그대로 맞았음. `logs:PutLogEvents` 권한 부재가 유일한 원인이었고, 다른 숨은 문제는 없었다.

**다음에 다시 할 때 참고할 것**:
- 이슈 #47에서 "Container Insights를 채택한다"로 결정되면, `modules/eks`(또는 노드그룹 IAM 모듈)에 `CloudWatchAgentServerPolicy` 부착을 Terraform으로 코드화하고 addon도 `aws eks create-addon` CLI 대신 Terraform(`aws_eks_addon`)으로 관리할 것 — 지금은 검증 목적의 임시 CLI 조작이었음.
- 검증 완료 후 원상복구: addon은 에이전트가 `delete-addon`으로 제거 가능하지만, 방금 붙인 IAM 정책 detach는 이번에도 "보안 설정 변경"이라 에이전트가 직접 할 수 없음 — 사용자가 `aws iam detach-role-policy --role-name slash-eks-node-dev --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy`를 직접 실행해야 완전히 원상복구됨(§8 마무리 체크리스트에 반영).

## 35. 부하테스트 3차 — 진짜 부하 도구(k6)로 스케일아웃 실증 + §22 문제 실제 재발 발견 (2026-08-31)

**시나리오**: §33에서 "동시성 300짜리 `ab`로는 CPU가 30%도 안 올라간다"고 결론 냈는데, 원인을 더 파보니 **`ab`(macOS 기본 번들, 오래된 단일 프로세스 빌드) 자체가 병목**이었다 — 동시성을 300→900으로 올려도 처리량이 그대로(~200 req/s)였고 Connect 시간만 더 늘어남(1.2s→2.8s), 이는 서버가 아니라 로컬 클라이언트가 그만큼의 동시 연결을 실제로 못 만들어내고 있다는 뜻. `brew install k6`로 제대로 된 부하 도구를 설치해 재시도.

**성공 기준**: 실제로 CPU 70%를 넘기는 부하를 만들어서 HPA가 스케일아웃하는지 최종 확인.

**타임라인** (UTC):
- 02:20~02:24 — `ab -c 900`으로 한 번 더 시도했으나 위 이유로 실패(처리량 그대로, Connect 시간만 폭증) → `ab` 자체의 한계로 결론, `brew install k6` 설치
- 02:25:48 — HPA/`kubectl top` 백그라운드 관측 시작
- 02:25:48~02:31:20 — k6 ramping-vus 시나리오 실행(0→200→500→800 VU, 총 5분30초): **총 1,347,475 요청, 4083 req/s 평균, 실패율 0.00%**
- 02:27~02:28 — HPA `cpu`가 **277%/70%**까지 치솟음(요청값 250m 기준 파드당 약 690m) → 거의 즉시 **4/4(max)로 스케일아웃**
- 02:28~02:31 — 4개 파드로 스케일아웃한 뒤에도 CPU가 **240~373%/70%**로 유지 — max replica(4)로도 이 정도 부하를 못 받아냄
- ALB 지표(같은 구간): `RequestCount` 최대 분당 417,888건(약 6,965 req/s), `HTTPCode_Target_5XX_Count` **총 1건**(사실상 무시할 수준), `TargetResponseTime` 평균 0.08~0.2초·최대 3.9~6.4초(포화 구간 지연)
- 02:31:20 — 부하 종료. 그런데 곧이어 **파드별 CPU가 극단적으로 불균등**하다는 걸 발견 — 새로 뜬 파드 2개(`5vwr9`, `rc6g7`)는 최대 1.8~1.9 코어까지 사용 중인데 기존 파드 2개(`gvq86`, `jpx5v`)는 계속 idle(7~30m)
- 02:32~02:33 — `aws elbv2 describe-target-health` 확인 → 기존 파드 2개가 **`unhealthy`(`Target.ResponseCodeMismatch`)**로 ALB 라우팅에서 빠져있었음. `kubectl get events`에서 같은 두 파드에 `Liveness probe failed: context deadline exceeded` 이벤트 확인(단, k8s 자체 `failureThreshold: 3` 문턱은 못 넘어서 컨테이너 재시작은 발생하지 않음)
- 02:33:33 — 부하 종료 후 **2분 넘게 지났는데도 회복 안 됨** — 임시 `curl` 파드로 두 파드 IP(8080)에 직접 요청했더니 **완전히 무응답**(TCP는 연결되나 3초 타임아웃까지 응답 없음), 반면 새 파드는 7ms에 정상 응답
- 02:34 — 두 파드의 최근 로그 확인 → **`FATAL: password authentication failed for user "slash_admin"`**, `HikariPool-1 - Connection is not available` 대량 발생 확인. `aws secretsmanager describe-secret`으로 RDS 관리형 마스터 비밀번호가 **당일 02:08:17 UTC에 자동 로테이션**된 사실 확인 — §22(2026-08-24)에서 발견했던 것과 **완전히 같은 원인의 재발**
- 02:35:21 — `kubectl rollout restart deployment/slash-api` 실행(원인 규명 후 즉시 복구 조치)
- 02:35:21 이후 — 롤아웃 정상 완료, 새 파드 4개 전부 `1/1 Running`, ALB 타겟 4개 전부 `healthy`로 복구 확인

**결과**: 성공 기준 완전 충족 — **HPA는 실제로 스케일아웃한다**(2→4, max까지). 다만 max replica(4)로도 이번 부하(약 5000~7000 req/s)를 못 받아내 CPU가 계속 250~370%대에 머물렀다는 것도 함께 확인됨(§5 인덱스에도 "성공 + 중요 발견"으로 반영).

**발견한 문제** (이번 회차가 가장 소득이 컸다):
1. **max replica(4)가 실제 트래픽 스파이크를 감당하기엔 부족할 수 있다.** 이번 정도 부하(k6 800 VU)에서도 스케일아웃 후 CPU가 여전히 250%+ 로 남았다 — `maxReplicas`를 늘리거나(노드그룹 `max=4`도 같이 늘려야 함) 파드당 `resources.requests.cpu`를 재산정할 필요가 있다는 신호.
2. **§22의 "RDS 관리형 비밀번호 로테이션 시 파드 고착" 문제가 실제로, 우연히, 오늘 다시 발생했다.** 이번엔 §22 때(로테이션 직후 우연히 걸린 파드가 CrashLoopBackOff로 눈에 띄게 실패)와 달리, **평소엔 기존 커넥션 풀을 재사용해 멀쩡해 보이다가 부하로 풀이 소진되는 순간에만 터지는 훨씬 은밀한 형태**였다. 게다가 k8s의 liveness probe(`failureThreshold: 3`)로는 감지가 안 돼 **자동 재시작도 안 되고, `kubectl get pods`로는 계속 정상(1/1 Running)으로 보임** — ALB 타겟 헬스만 보고 있지 않았다면 놓쳤을 문제. 이슈 [#80](https://github.com/LikeLionTeam4/slash-infra/issues/80)으로 등록, Reloader 도입을 정식 제안함.
3. ALB 타겟 그룹 알고리즘은 `round_robin`이라 "일부러" 불균형하게 보낸 게 아니라, **헬스체크에 떨어진 타겟을 정상적으로 라우팅에서 제외한 것**뿐이었다 — 처음엔 알고리즘 문제로 의심했으나 `describe-target-group-attributes`로 확인 후 배제.

**다음에 다시 할 때 참고할 것**:
- 로컬 부하테스트는 `ab`가 아니라 `k6`(또는 `hey`, `wrk` 등 진짜 동시성을 만들어내는 도구)를 쓸 것 — `ab`는 동시성을 아무리 올려도 처리량이 안 늘어나는 걸 이번에 실측으로 확인함.
- **RDS 관리형 비밀번호 로테이션 스케줄(`NextRotationDate`)을 사전에 확인하고, 로테이션 시점 근처(±1시간, `refreshInterval` 기준)에는 부하테스트를 피하거나, 반대로 일부러 그 타이밍에 맞춰 이 문제를 재현/검증하는 것도 유효한 전략.**
- `maxReplicas`를 늘리는 결정을 한다면 EKS 노드그룹 `max`(현재 4)도 함께 늘려야 실제로 스케줄링 가능 — HPA 상한만 올리는 건 의미 없음.
- 이번에도 원인 파악 후 조치(`rollout restart`)까지 바로 실행 — §31에서 얻은 "로테이션 이후엔 무조건 재시작"이라는 교훈이 이번엔 사후 대응이 아니라 사전 지식으로 바로 적용된 사례.

## 36. Reloader 도입 검증 (2026-08-31)

**시나리오**: §35에서 실제로 재발한 §22 문제(RDS 비밀번호 로테이션 시 파드 고착)에 대한 근본 대책으로 이슈 [#80](https://github.com/LikeLionTeam4/slash-infra/issues/80)에서 제안한 Reloader(stakater/reloader)를 실제로 도입하고, Secret이 바뀌면 정말로 자동 롤링 재시작이 되는지 검증. `helm/slash-api/templates/deployment.yaml`에 `secret.reloader.stakater.com/reload: "slash-api-secrets"` annotation을 추가하는 코드 변경은 커밋했지만 **아직 push 전**이라(로컬 11개 커밋이 origin 대비 앞서있는 상태), ArgoCD가 GitHub에서 pull하는 구조상 이 annotation은 아직 실제 클러스터엔 반영되지 않은 상태였다 — push하기 전에 먼저 검증부터 하기로 함(사용자 지시).

**성공 기준**: Secret 내용이 바뀌면 Reloader가 감지해서 `slash-api` Deployment가 자동으로 롤링 재시작되는지 확인.

**타임라인** (UTC):
- 02:47:59~02:48:05 — `helm repo add stakater` → `helm install reloader stakater/reloader -n kube-system`로 컨트롤러 설치(다른 클러스터 내부 애드온과 동일하게 GitOps 대상 아님, `reloader/README.md`로 문서화)
- 02:50:49 — push 전에 검증하기 위해 §30과 같은 방법으로 `slash-api` ArgoCD Application의 `syncPolicy.automated`를 임시로 해제(§30 GitHub 리허설 때와 동일한 patch 방식)
- 이어서 `kubectl annotate deployment slash-api secret.reloader.stakater.com/reload=slash-api-secrets`로 커밋해둔 chart 변경을 라이브 Deployment에 수동으로 미리 반영(annotation만 추가라 이 자체로는 롤아웃 안 일어남 — revision 57 그대로 유지 확인)
- 03:11:22 — 실제 DB_USERNAME/DB_PASSWORD/VALKEY_AUTH_TOKEN은 건드리지 않고, `slash-api-secrets`에 아무 의미 없는 테스트 키(`RELOADER_TEST`)를 `kubectl patch secret --type merge`로 추가(보안 설정 변경으로 분류돼 에이전트가 직접 실행 못 해 사용자가 직접 실행)
- 03:11:22 (같은 시각, 로그 2건) — `reloader-reloader` 파드 로그에 `Changes detected in 'slash-api-secrets' of type 'SECRET' in namespace 'default'; updated 'slash-api' of type 'Deployment'` 즉시 기록 — 아마 ESO가 매니지드 시크릿에 없는 키를 거의 즉시 원래 3개 키로 되돌리면서 두 번째 변경도 함께 감지된 것으로 추정
- 이어서 — `kubectl rollout history`에 새 revision 58, 59 생성 확인, `kubectl rollout status` 정상 완료(`kubectl.kubernetes.io/restartedAt` annotation이 pod template에 자동으로 붙은 것으로 트리거 방식 확인), 새 파드 전부 `1/1 Running`

**결과**: 성공 기준 완전 충족. Secret 값이 바뀌면 **사람 개입 없이, 1시간 `refreshInterval`을 기다릴 필요도 없이, 수 초 안에** 자동 롤링 재시작된다는 걸 실측으로 확인. §22/§35의 근본 원인(파드가 옛 Secret에 영구 고착)이 이제 구조적으로 해결됨.

**발견한 문제**: 없음 — 의도한 대로 정확히 동작함. 다만 테스트 키를 추가하자마자 ESO가 되돌리면서 변경이 두 번 감지된 것으로 보이는데, 정확한 인과관계까지는 확인 못 했음(중요하지 않아 더 파지 않음).

**다음에 다시 할 때 참고할 것**:
- 검증은 실제 값(DB_PASSWORD 등)을 건드리지 않고 무해한 테스트 키 하나만 추가하는 방식으로 진행해 기능 리스크 없이 확인 가능했다 — 이후에도 이 패턴을 재사용할 것.
- `kubectl patch secret`은 "보안 설정 변경"으로 분류돼 에이전트가 직접 실행할 수 없음 — Secret 관련 검증은 항상 사용자 실행이 필요하다는 점을 미리 안내할 것.
- **아직 push 전** — `helm/slash-api/templates/deployment.yaml`의 annotation과 `reloader/README.md`가 origin에 반영돼야 ArgoCD가 selfHeal을 켠 상태에서도 이 annotation을 유지한다. push 전까지는 `slash-api` Application의 `syncPolicy.automated`를 해제된 상태로 둬야 함(§8류 마무리 체크리스트에 반영 필요) — push 완료 후 `{"automated":{"prune":true,"selfHeal":true}}`로 복원할 것.

## 37. Secrets 유출 대응 리허설 재검증 — 옛 토큰 무효화 확인 + ROTATE/SET 전략 버그 발견 (2026-08-31)

**시나리오**: §31에서 "직접 검증하지 못함"으로 남겨뒀던 부분 — Valkey AUTH 토큰을 로테이션하면 **옛 토큰이 실제로 즉시 거절되는지** — 을 재검증. 이번엔 로테이션 직전에 옛 토큰을 미리 백업해뒀다가 로테이션 후 그 옛 토큰으로 직접 연결을 시도하는 방식으로 §31의 절차를 그대로 반복하되 한 단계만 추가.

**성공 기준**: 로테이션 후 새 토큰은 연결되고(PONG), 옛 토큰은 거절돼야(WRONGPASS/NOAUTH) 진짜 "유출 무효화"가 확인된 것.

**타임라인** (UTC):
- 03:41:56 — `aws secretsmanager get-secret-value`로 로테이션 전 옛 토큰을 스크래치 디렉터리에 백업(레포에는 커밋 안 함, 사용 후 즉시 삭제 예정)
- 03:42:12~03:42:47 — §31과 동일하게 `terraform apply -replace=module.database.random_password.valkey_auth` 실행(영향 범위도 §31과 동일하게 3개 리소스만)
- 03:42:56~03:44:30 — **로테이션 완료 직후부터 옛 토큰으로 5회 연속 `redis-cli ping` 시도 → 전부 `PONG`.** 즉 §31에서 "구조적으로 더 이상 유효하지 않을 것"이라 판단했던 게 **틀렸다는 게 실측으로 드러남**
- 원인 확인 — `modules/database/valkey.tf`에 `auth_token_update_strategy`를 명시적으로 지정한 적이 없어 AWS 기본값(`ROTATE`)이 적용되고 있었음. `ROTATE`는 무중단 교체를 위해 신구 토큰을 **당분간 둘 다 허용**하는 전략이고, 이걸 실제로 완전히 무효화하려면 후속으로 `SET` 전략의 apply가 한 번 더 필요하다는 걸 이번에 처음 알게 됨(§31 때는 이 전략 파라미터 자체의 존재를 몰랐음)
- `modules/database/valkey.tf`의 `aws_elasticache_replication_group.main`에 `auth_token_update_strategy = "SET"` 추가(코드에 영구 반영 — 이 시스템에서 토큰을 바꾸는 유일한 이유는 보안 위생/유출 대응이라 "즉시 무효화"가 기본값으로 맞다고 판단)
- 03:45:47~03:46:02 — `terraform apply`로 전략을 `ROTATE`→`SET`으로 변경(다른 리소스에 영향 없음, `auth_token_update_strategy` 속성 하나만 in-place 변경)
- 03:46:12 — 옛 토큰으로 재시도 → **`WRONGPASS invalid username-password pair`** 로 거절 확인. 같은 시각 새 토큰은 여전히 `PONG` — 이번엔 확실하게 "새 토큰만 유효, 옛 토큰은 완전히 무효" 상태 확인
- 03:46:32 — `kubectl annotate externalsecret slash-api-secrets force-sync=$(date +%s) --overwrite`로 강제 동기화
- 03:46:34 — **§36에서 막 도입한 Reloader가 이 진짜 시크릿 변경을 자동으로 감지**(`reloader-reloader` 로그에 `Changes detected in 'slash-api-secrets' ... updated 'slash-api'`) → **사람이 `kubectl rollout restart`를 실행하지 않았는데도** 새 파드가 자동으로 뜨기 시작
- 이후 — 롤아웃 정상 완료, 새 파드 2/2 `Running`(재시작 0회), 최근 로그에 Valkey 관련 에러 전혀 없음, ALB 타겟 정상 `healthy`로 전환

**결과**: 성공 기준 완전 충족. 옛 토큰 무효화까지 직접 확인했고, 그 과정에서 §31의 잘못된 결론(ROTATE 기본값 때문에 실제로는 무효화가 안 되고 있었던 것)까지 바로잡았다. 덤으로 Reloader가 **실제 운영 시나리오(진짜 토큰 로테이션)에서 사람 개입 없이 정상 동작**하는 것까지 한 번에 검증됨 — §36은 무해한 테스트 키로 검증한 거였다면, 이번엔 진짜 상황으로 검증한 셈.

**발견한 문제**:
1. **§31이 검증 없이 내린 결론이 실제로 틀렸었다.** "ROTATE 단계를 안 거쳤으니 구조적으로 무효화될 것"이라는 추측은 `auth_token_update_strategy` 파라미터의 존재 자체를 몰랐기 때문에 나온 잘못된 근거였다. 검증 없이 "구조적으로 그럴 것"이라고 판단하는 게 왜 위험한지 보여주는 사례 — §31에 정정 각주를 남겨둠.
2. Terraform이 리소스를 in-place로 "성공적으로 업데이트"했다고 보고해도, 그게 우리가 원하는 실제 동작(즉시 무효화)과 일치하는지는 별개로 확인해야 한다는 교훈 — `terraform apply`가 초록색으로 끝나는 것과 "의도한 보안 효과가 실제로 발생했는지"는 다른 질문.

**다음에 다시 할 때 참고할 것**:
- 이제 `auth_token_update_strategy = "SET"`이 코드에 고정돼 있으니, 앞으로의 Valkey 토큰 로테이션은 별도 조치 없이도 즉시 무효화된다 — §31/§37에서 했던 "로테이션 전 옛 토큰 백업" 단계는 검증 목적이 아니라면 이제 불필요.
- RDS 쪽도 관리형 비밀번호 로테이션에 비슷한 "이전 값 유예기간" 개념(`rds:PENDING`/`rds:CURRENT`/`rds:PREVIOUS` 라벨)이 있는지 한 번쯤 확인해볼 가치가 있음 — 이번처럼 "당연히 즉시 무효화될 것"이라는 가정이 또 틀렸을 수도 있음(범위 밖이라 이번엔 확인 안 함).
- Reloader가 실전 시나리오에서도 검증됐으니, §22/§35 재발 가능성은 이제 "이론상 남은 리스크"가 아니라 "실제로 막힌 문제"로 결론 내려도 됨.

## 38. CloudFront/S3 오리진 차단 재검증 — 캐시 hit 경로도 안 살아남는다 (2026-08-31)

**시나리오**: §29에서 "미검증"으로 남겨뒀던 부분 — 오리진이 막혀도 **이미 엣지에 캐시된 자산은 계속 정상 서빙되는지** — 를 재검증. 캐시된 정적 자산과 캐시 안 된(쿼리스트링으로 무력화한) 요청을 나란히 비교.

**성공 기준**: 캐시 hit 경로는 오리진 차단과 무관하게 200으로 계속 서빙되고, 캐시 miss 경로만 실패해야 "캐싱이 실제로 가용성에 기여한다"고 할 수 있음.

**타임라인** (UTC):
- 03:5x — 사전 확인: `/assets/index-6JmV0NgU.js`(해시 붙은 빌드 산출물, `Cache-Control: public,max-age=31536000,immutable`)를 반복 요청해 `x-cache: RefreshHit from cloudfront`(엣지 `ICN80-P2`) 확인 — 캐시된 상태임을 먼저 증명
- 03:56:41 — §29와 동일한 방법으로 S3 버킷 정책에 `Deny` 문 추가(정책 백업 먼저)
- 즉시 이어서 3가지를 동시에 테스트:
  - **캐시된 JS 자산을 그대로 재요청** → 예상: 200(캐시에서 서빙) / 실제: **`HTTP 403`, `x-cache: Error from cloudfront`, 응답 바디가 S3 AccessDenied XML** — 캐시에서 안 나가고 오리진 재검증을 시도하다 그대로 실패
  - 같은 자산을 쿼리스트링으로 캐시 무력화해서 요청(강제 캐시 miss) → `403`, 동일한 AccessDenied XML — 예상대로 실패
  - `index.html` → `403` — §29와 동일
- 03:57:09 — 정책 원복(차단 지속 28초), 3초 뒤 재확인 → `index.html`/JS 자산 전부 `200`으로 즉시 정상화

**결과**: **캐시 hit 경로도 오리진 차단에서 살아남지 못한다** — §29 때 "혹시 캐시된 건 괜찮지 않을까"라는 여지를 남겨뒀는데, 실측 결과는 명확히 "아니오"였다.

**발견한 문제**:
1. **CloudFront의 "stale content 서빙" 동작은 오리진의 5xx/타임아웃에만 적용되고, 이번처럼 오리진이 403(명시적 거부)을 반환하는 경우엔 적용되지 않는다.** `RefreshHit` 상태의 객체(만료 임박이라 백그라운드로 오리진에 재검증하는 상태)가 하필 그 재검증 시도 타이밍에 오리진이 막혀 있으면, 캐시에 있는 멀쩡한 바이트를 서빙하는 대신 오리진의 403 에러를 그대로 클라이언트에 전달한다 — "캐시가 있으니 오리진이 잠깐 막혀도 사용자는 못 느낄 것"이라는 가정이 틀렸다는 뜻. `Error from cloudfront` 상태 자체가 이 사실을 그대로 보여준다.
2. 완전히 갓 캐시되어 재검증 타이밍과 안 겹치는 객체라면 결과가 다를 수도 있다(이번엔 하필 `RefreshHit` 타이밍에 걸린 것) — 이 케이스(재검증이 전혀 필요 없는, 방금 막 캐시된 객체)까지는 이번에 확인 못 함. 다만 실무적으로 "언젠가는 재검증 타이밍과 겹칠 수 있다"는 점에서 캐싱을 가용성 대책으로 믿기는 어렵다는 결론엔 변함없음.

**다음에 다시 할 때 참고할 것**:
- "캐싱돼 있으니 오리진 장애에 어느 정도 버틸 것"이라는 가정은 이번 계정/설정 기준으로는 성립하지 않는다 — §13(오리진 페일오버 부재) 논의에 이 사실도 같이 반영할 것.
- CloudFront의 "Origin Shield"나 캐시 동작 설정에 "오리진 5xx 시 stale 콘텐츠 서빙" 옵션이 있는지, 있다면 403에도 적용되는 변형이 있는지는 이번 범위 밖이라 확인 안 함 — 진짜 가용성을 높이고 싶다면 이 옵션 존재 여부부터 조사해볼 가치 있음.
- §29의 성공 기준 문구("캐시된 자산은 계속 서빙되는지 확인") 자체를 "캐시 hit이어도 살아남지 못함을 확인"으로 갱신 — §5 인덱스에도 반영.

## 39. dev 환경 전체 destroy — `Project=slash` 태그 자원 + 개인 생성 자원 정리 (2026-09-03)

§19에서 상시운영으로 전환된 이후 처음으로 `environments/dev` 전체를 destroy했다(팀원 3명의 EKS 접근·CI/CD 자동배포에 영향, 사전 확인 후 진행). `bootstrap`(ECR 3개, Route53 zone, CloudTrail, backend-cicd Role 3개, tfstate 버킷, Budgets)은 계정 공용 자원이라 유지.

**순서**: K8s 레벨 정리 → `observability` → `eks` → `database` → `cognito` → `network`(flow-log 버킷 비우기 선행) → `frontend`. §5 destroy 절차(local 기준)의 "뒤 단계부터" 원칙을 dev 6개 모듈에 그대로 적용.

**트러블슈팅**:
- **ArgoCD selfHeal 재생성 방지**: `slash-api`/`slash-nlu` Application 둘 다 `{"prune":true,"selfHeal":true}` 확인됨 — §4의 "destroy 중 ArgoCD selfHeal이 Ingress를 되살려 orphan ALB 재생성" 사고가 그대로 재현될 조건이라, Ingress/Service 삭제보다 먼저 Application부터 지워서 회피.
- **ALB Controller의 공유 백엔드 SG가 DependencyViolation으로 삭제 실패**: Ingress를 지운 뒤 finalizer(`ingress.k8s.aws/resources`)가 안 풀려서 보니, 컨트롤러 로그에 `failed to delete securityGroup: ... DependencyViolation: resource sg-xxx has a dependent object`. 원인은 EKS 노드 SG(`slash-eks-sg-dev`)에 이 백엔드 SG를 참조하는 인바운드 룰(`elbv2.k8s.aws/targetGroupBinding=shared` 태그, 컨트롤러가 자동 생성)이 남아있어서였다. Service를 Ingress보다 먼저 지운 게 원인으로 보임(컨트롤러가 정리 모델을 재계산할 시점엔 이미 대상이 사라져 룰 revoke를 놓친 듯). `aws ec2 revoke-security-group-ingress`로 해당 룰만 직접 제거하니 다음 reconcile에서 정상 정리됨. **교훈**: Ingress delete가 완전히 끝난 뒤(ALB/타겟그룹/SG까지 AWS에서 사라진 걸 확인한 뒤) Service/Deployment를 지우는 순서를 지킬 것.
- **Karpenter NodePool을 먼저 지운 게 실수**: `kubectl delete nodepool default` 후 `kubectl delete nodeclaims --all`을 했더니 NodeClaim이 `NodePool.karpenter.sh "default" not found` 에러로 계속 reconcile 실패 — NodePool은 NodeClaim이 전부 종료된 *뒤에* 지워야 했다. 게다가 karpenter 컨트롤러 파드 자체가 3시간 넘게 `Pending`이었던 것도 함께 발견: karpenter Deployment의 nodeAffinity가 `karpenter.sh/nodepool DoesNotExist`(자기 자신이 만든 노드에는 못 뜨는 순환 방지 설계)인데, 관리형 노드그룹(`slash-eks-general-dev`)이 `desired=0`으로 스케일다운돼 있어 karpenter가 뜰 노드 자체가 없었다 — dev 상시운영 체제인데도 nodegroup이 0으로 가 있었던 것 자체가 별개의 잠재 이슈(다음에 조사 필요, 야간 스케줄러 §21과 관련 있을 가능성). **조치**: nodegroup을 1대로 임시 스케일업 → karpenter 재기동 확인 후에도 NodePool 참조 에러가 안 풀려서, EC2 인스턴스 4대를 `aws ec2 terminate-instances`로 직접 종료하고 NodeClaim의 `karpenter.sh/termination` finalizer를 `kubectl patch`로 직접 제거해 정리. 인스턴스 4대 중 3대는 이미 예전에 terminated 상태였던 고아 NodeClaim이었다(원인 미상, 이번 조사 범위 밖).
- **`dev/observability`의 `data "aws_lb" "slash_api"`가 destroy plan도 막음**: 코드 주석(line 67)에 이미 "Ingress를 잠깐이라도 내려서 ALB가 사라진 상태로 apply하면 이 data source가 실패한다"고 경고돼 있었는데, `-destroy` plan도 동일하게 막힌다는 걸 이번에 확인. ALB를 K8s 레벨 정리에서 먼저 지웠기 때문에 발생. **조치**: `alb_arn_suffix`를 더미값으로, data 블록을 주석 처리해 destroy만 통과시킨 뒤 `git checkout`으로 원복(커밋 안 함) — 값 자체는 destroy에 안 쓰이므로(상태 기준으로 리소스 ID만으로 삭제) 안전.
- `slash-vpc-flow-logs-dev` 버킷: 버저닝 활성 + `force_destroy` 미설정 상태로 9,738개 객체/버전이 쌓여있었다(§10-3 local 사례의 20배 이상 규모) — `list-object-versions`/`delete-objects`를 1,000개씩 배치 처리해 비운 뒤 `network` destroy 진행.
- `slash-web-dev` 버킷은 의도된 `force_destroy=false`(§ 코드 주석 "실수로 지우는 걸 막는다")라 오브젝트 8개를 `aws s3 rm --recursive`로 수동 삭제 후 destroy.
- ACM 인증서는 예상대로 2개였다 — `api.dev.sbsh.cloud`(ap-northeast-2, `dev/eks` 소유, ALB용)와 `dev.sbsh.cloud`(us-east-1, `dev/frontend` 소유, CloudFront용). 둘 다 각자 모듈 destroy에 포함돼 정상 제거됨.

**검증**: `aws resourcegroupstaggingapi get-resources --tag-filters Key=Project,Values=slash`로 재조회하면 아직 캐시 지연으로 destroy된 리소스가 보이지만(EC2/NAT/Cognito 등, 최대 수십 분 지연 알려진 동작), `describe-instances`/`describe-nat-gateways`/`describe-vpcs`/`describe-user-pool` 등 실시간 API로 개별 재확인한 결과 전부 실제로 삭제 완료됨. 잔여는 bootstrap 소유 6종뿐. Secrets Manager의 `slash/valkey/dev`는 기본 30일 복구 대기 중(`DeletedDate` 설정됨, 영구 삭제 아님) — RDS managed secret(`rds!db-11d47fea-...`)은 RDS 인스턴스 삭제와 함께 즉시 제거됨(복구 대기 없음, 관리형 시크릿의 정상 동작).

**남은 후속 확인**: 관리형 노드그룹이 상시운영 체제에서도 `desired=0`으로 가 있었던 원인(야간 스케줄러 §21 관련 가능성) — 이번엔 전체 destroy로 덮여서 실증 안 됨, dev를 다시 올리게 되면 재확인할 것.
