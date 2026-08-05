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
| 5 | EKS + EC2(3대) + ECR | ✅ 코드 완료, **apply→검증→destroy 완료(현재는 미적용)** | 2번의 `private_app_subnet_ids`, `eks_security_group_id` 필요. 4번과는 서로 독립적 | 2번(network)**보다 먼저** 지워야 함(서브넷/SG를 참조 중). ECR도 `force_delete` 안 켜놔서 이미지 있으면 비우거나 옵션 추가 필요(§4 flow_logs 버킷과 같은 패턴) |
| 6 | ALB Ingress + API용 ACM | ⬜ 미구현 | 5번(로드밸런서 컨트롤러) + 1번(zone) 필요 | (미구현) |
| 7 | CloudWatch 알람(`modules/observability`) | ✅ 코드 완료, **apply→검증→destroy 완료(현재는 미적용)** (RDS CPU/스토리지만, ALB·GPU 알람은 6번·GPU 노드그룹 생기면 추가) | 4번의 `rds_instance_id` 필요 | 4번(database)**보다 먼저** 지워야 함(§5-2, 알람이 그 인스턴스ID를 참조) |

- **1·2번은 서로 의존이 없어서 순서를 바꾸거나 동시에 apply해도 무방**하다. 3번(frontend)부터는 1번이 먼저 끝나 있어야 하고, 4번(RDS+Valkey)·5번(EKS)은 둘 다 2번(network)의 서브넷·SG를 참조하므로 2번이 먼저 있어야 한다. 4번과 5번은 서로 무관 — 순서 상관없음. 7번(CloudWatch)은 4번 다음.
- **Destroy는 표 번호의 역순이 기본**이지만, 4·5번은 2번을, 7번은 4번을 참조하고 있어서 각각 **참조 대상보다 반드시 먼저** 지워야 한다.
- dev/prod 환경 자체는 아직 미구축 — 계정 구조는 `docs/aws-architecture.md` §11 참고 (local은 팀원마다 다른 계정, prod는 담당자 2명이 계정 하나 공유).

## 2. 현재 적용 상태

| 환경 | 리소스 수 | 핵심 output | 상태 |
| --- | --- | --- | --- |
| `environments/bootstrap` | 5 | `route53_zone_id = Z03858108FMADVU36PUA`, `bucket_name = slash-tfstate-727646470302` | 적용됨 |
| `environments/local/network` | 38 | `vpc_id = vpc-0e99fcc8dcea839a0`, NAT 1개(`ap-northeast-2a`) | 적용됨 |
| `environments/local/frontend` | 12 | `site_url = https://local.sbsh.cloud`, `bucket_name = slash-web-local-727646470302`, `frontend_deploy_role_arn = arn:aws:iam::727646470302:role/slash-frontend-deploy-local` | 적용됨, 콘텐츠까지 배포됨. GitHub OIDC 배포 Role(`modules/frontend-cicd`) 추가 적용(2026-08-05) |
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

## 6. 이 문서 갱신 규칙

- RDS/Valkey, EKS/EC2, ALB Ingress 등 새 모듈을 apply하면 §1(전체 순서, 구현 열을 ✅로)과 §2(현재 적용 상태), §3(Apply 이력)에 반영한다.
- apply/destroy 중 예상 못 한 에러를 만나면 §4(트러블슈팅 기록)에 원인·조치·교훈을 남긴다 — 다음에 같은 실수를 반복하지 않는 게 목적.
- destroy 절차(§5)는 새 환경이 추가될 때마다(특히 서로 참조하는 관계가 생기면) 순서를 다시 검토한다.
