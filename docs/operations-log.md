# 운영 로그 (Apply / Destroy 기록)

`docs/aws-architecture.md`가 "무엇을 왜 이렇게 설계했는가"를 다루는 설계 문서라면, 이 문서는 **실제로 AWS에 뭘 적용했고, 지우려면 뭘 해야 하는지**를 다루는 운영 기록이다. 인프라가 늘어날 때마다(RDS, EKS, dev/prod 환경 등) 계속 갱신되는 **살아있는 문서** — 아래 각 섹션을 그때그때 추가/수정한다.

> **주의**: 아래 리소스 ID·도메인은 특정 AWS 계정(`727646470302`) 하나에서 실습한 결과다. 부트캠프 계정은 사람마다 따로 발급되므로, 다른 계정에서 시작한다면 이 값들은 안 맞고 처음부터 다시 apply해야 한다 — [README §다른 AWS 계정에서 시작하기](../README.md#다른-aws-계정에서-시작하기-팀원용) 참고.

## 1. 전체 순서 & 구현 상태 한눈에 보기

Apply는 이 표의 순서대로, **Destroy는 반대 순서**로 진행한다. "구현" 열이 ⬜(미구현)인 건 아직 모듈/코드 자체가 없다는 뜻 — 순서는 앞으로 만들 때를 대비한 계획이다.

| # | 환경 / 모듈 | 구현 | Apply 조건 (뭐가 있어야 되는지) | Destroy 시 주의사항 |
| --- | --- | --- | --- | --- |
| 1 | `environments/bootstrap` (state+DNS+**CloudTrail**) | ✅ 적용됨(state+DNS) / **CloudTrail만 코드 완료, 미적용** | 없음 — 가장 먼저 | **가장 마지막에.** `prevent_destroy` 코드에서 제거해야 destroy 가능(§5-5). zone 지우면 `sbsh.cloud` DNS 전체가 끊김 |
| 2 | `environments/local/network` | ✅ 적용됨 | 없음 — 1번과 순서 무관, 독립적 | 4·5번(database/eks)**보다 나중에** 지워야 함(§5-3, §5-4) |
| 3 | `environments/local/frontend` (+ `modules/frontend-cicd` 배포 Role) | ✅ 적용됨 | 1번의 `hosted_zone_id` 필요 | **가장 먼저.** zone 안에 이 모듈이 만든 레코드가 있어서(§5-1) — `force_destroy=true`라 버킷 비우기는 불필요. CI Role은 이 환경 destroy 시 같이 지워짐(별도 조치 불필요) |
| 4 | RDS + Valkey + Secrets Manager | ✅ 코드 완료, **apply→검증→destroy 완료(현재는 미적용)** | 2번의 `private_db_subnet_ids`, `db_security_group_id` 필요 | 2번(network)**보다 먼저** 지워야 함(서브넷/SG 참조). local은 `deletion_protection=false`+`skip_final_snapshot=true`라 바로 destroy 가능 |
| 5 | EKS + EC2(3대) + ECR + ALB Controller Role | 클러스터/노드그룹/ALB Controller Role은 ✅ 코드 완료, **두 번째 apply→검증(ALB Controller+Helm chart 포함)→destroy까지 완료**(2026-08-11, §3). **ECR만 계속 적용된 상태로 유지 중** | 2번의 `private_app_subnet_ids`, `eks_security_group_id` 필요. 4번과는 서로 독립적. ECR은 이 둘과 무관 — 클러스터 없이도 apply 가능 | 2번(network)**보다 먼저** 지워야 함(서브넷/SG를 참조 중). ECR도 `force_delete` 안 켜놔서 이미지 있으면 비우거나 옵션 추가 필요(§4 flow_logs 버킷과 같은 패턴) — 단 `mock-*` 태그는 lifecycle policy가 3일 후 자동 정리하므로 그 이미지들 때문에 막힐 일은 없음. **ALB Controller로 Ingress를 만든 적이 있다면 클러스터 destroy 전에 반드시 `kubectl delete ingress`부터 해야 함**(§4 참고) |
| 6 | ALB Ingress + API용 ACM | ⬜ 미구현 | 5번(로드밸런서 컨트롤러) + 1번(zone) 필요 | (미구현) |
| 7 | CloudWatch 알람(`modules/observability`) | ✅ 코드 완료, **apply→검증→destroy 완료(현재는 미적용)** (RDS CPU/스토리지만, ALB·GPU 알람은 6번·GPU 노드그룹 생기면 추가) | 4번의 `rds_instance_id` 필요 | 4번(database)**보다 먼저** 지워야 함(§5-2, 알람이 그 인스턴스ID를 참조) |
| 8 | Cognito(`modules/cognito`, User Pool+Client+Domain, Managed Login) | ✅ 적용됨, **상시 유지**(slash-web/slash-api가 이 User Pool ID·Client ID를 직접 참조하므로 database/eks처럼 검증 후 destroy하지 않는다) — 이메일+비밀번호만, Google 소셜 로그인은 채택 안 하기로 결정(2026-08-05) | 없음 — 1·2번과 무관, 완전히 독립적(VPC 안 씀) | 다른 모듈과 참조 관계 없어서 순서 무관이지만, slash-web/slash-api 로컬 설정이 이 값에 의존하므로 팀에 미리 알리지 않고 지우지 말 것 |

- **1·2·8번은 서로 의존이 없어서 순서를 바꾸거나 동시에 apply해도 무방**하다. 3번(frontend)부터는 1번이 먼저 끝나 있어야 하고, 4번(RDS+Valkey)·5번(EKS)은 둘 다 2번(network)의 서브넷·SG를 참조하므로 2번이 먼저 있어야 한다. 4번과 5번은 서로 무관 — 순서 상관없음. 7번(CloudWatch)은 4번 다음. 8번(Cognito)은 VPC를 쓰지 않는 리전 서비스라 다른 모든 모듈과 무관.
- **Destroy는 표 번호의 역순이 기본**이지만, 4·5번은 2번을, 7번은 4번을 참조하고 있어서 각각 **참조 대상보다 반드시 먼저** 지워야 한다.
- dev/prod 환경 자체는 아직 미구축 — 계정 구조는 `docs/aws-architecture.md` §11 참고 (local은 팀원마다 다른 계정, prod는 담당자 2명이 계정 하나 공유).

## 2. 현재 적용 상태

| 환경 | 리소스 수 | 핵심 output | 상태 |
| --- | --- | --- | --- |
| `environments/bootstrap` | 5 | `route53_zone_id = Z03858108FMADVU36PUA`, `bucket_name = slash-tfstate-727646470302` | 적용됨 |
| `environments/local/network` | 38 | `vpc_id = vpc-0e99fcc8dcea839a0`, NAT 1개(`ap-northeast-2a`) | 적용됨 |
| `environments/local/frontend` | 12 | `site_url = https://local.sbsh.cloud`, `bucket_name = slash-web-local-727646470302`, `frontend_deploy_role_arn = arn:aws:iam::727646470302:role/slash-frontend-deploy-local` | 적용됨, 콘텐츠까지 배포됨. GitHub OIDC 배포 Role(`modules/frontend-cicd`) 추가 적용(2026-08-05) |
| `environments/local/cognito` | 3 | `user_pool_id = ap-northeast-2_s2ZnfGrqo`, `user_pool_client_id = 4g9h0vsvel02drlieqbg9n9nhi`, `issuer_url = https://cognito-idp.ap-northeast-2.amazonaws.com/ap-northeast-2_s2ZnfGrqo`, `hosted_domain = https://slash-local-727646470302.auth.ap-northeast-2.amazoncognito.com` | 적용됨, 상시 유지. Managed Login(v2) + 이메일·비밀번호. slash-web/slash-api가 이 값들을 직접 참조하므로 destroy 금지 |
| `environments/local/eks` (ECR만) | 6 | `ecr_repository_urls = {slash-api, slash-nlu, slash-llm}` (계정 `727646470302`) | **ECR만 적용된 상태로 유지(2026-08-11)** — 클러스터+노드그룹+ALB Controller Role은 검증 끝나고 destroy 완료(§3). 클러스터/ALB Controller/Helm chart(`helm/`) 검증 이력은 §3에 남아있음, 다시 필요할 때 `terraform apply`(전체) + `helm install`로 재현 가능 |
| `environments/dev/*` | – | – | 미구축 |
| `environments/prod/*` | – | – | 미구축 |

계정은 `727646470302`(부트캠프 공유), 리전 `ap-northeast-2`. 이 표는 스냅샷이라 실제 값이 궁금하면 각 디렉터리에서 `terraform output`으로 재확인할 것 — 아래는 마지막 갱신 시점(2026-08-05) 기준.

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

### Terraform 1.15.8엔 `-exclude` 플래그가 없음 (2026-08-11)

ECR은 남기고 나머지만 destroy하려고 `terraform destroy -exclude=...`를 시도했다가 "flag provided but not defined" 에러를 만났다.

- **원인**: `-exclude`(target의 반대, "이것만 빼고 전부")는 실제로 존재하는 플래그가 아니다 — 착각이었다. Terraform은 `-target`(이것만 포함)만 지원한다.
- **조치**: `terraform state list`로 전체 리소스를 뽑은 뒤 `grep -v`로 ECR 관련 6개를 제외하고, 나머지 16개를 전부 `-target`으로 나열해서 destroy했다.
- **교훈**: "일부만 빼고 나머지 전부"가 필요하면 `-target` 여러 개를 나열하는 것 말고 방법이 없다 — 리소스가 많으면 `terraform state list | grep -v ...`로 목록을 뽑아 스크립트로 `-target` 인자를 생성하는 편이 손으로 나열하는 것보다 안전하다.

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
