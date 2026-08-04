# 운영 로그 (Apply / Destroy 기록)

`docs/aws-architecture.md`가 "무엇을 왜 이렇게 설계했는가"를 다루는 설계 문서라면, 이 문서는 **실제로 AWS에 뭘 적용했고, 지우려면 뭘 해야 하는지**를 다루는 운영 기록이다. 인프라가 늘어날 때마다(RDS, EKS, dev/prod 환경 등) 계속 갱신되는 **살아있는 문서** — 아래 각 섹션을 그때그때 추가/수정한다.

> **주의**: 아래 리소스 ID·도메인은 특정 AWS 계정(`727646470302`) 하나에서 실습한 결과다. 부트캠프 계정은 사람마다 따로 발급되므로, 다른 계정에서 시작한다면 이 값들은 안 맞고 처음부터 다시 apply해야 한다 — [README §다른 AWS 계정에서 시작하기](../README.md#다른-aws-계정에서-시작하기-팀원용) 참고.

## 1. 전체 순서 & 구현 상태 한눈에 보기

Apply는 이 표의 순서대로, **Destroy는 반대 순서**로 진행한다. "구현" 열이 ⬜(미구현)인 건 아직 모듈/코드 자체가 없다는 뜻 — 순서는 앞으로 만들 때를 대비한 계획이다.

| # | 환경 / 모듈 | 구현 | Apply 조건 (뭐가 있어야 되는지) | Destroy 시 주의사항 |
| --- | --- | --- | --- | --- |
| 1 | `environments/bootstrap` | ✅ 적용됨 | 없음 — 가장 먼저 | **가장 마지막에.** `prevent_destroy` 코드에서 제거해야 destroy 가능(§5-3). zone 지우면 `sbsh.cloud` DNS 전체가 끊김 |
| 2 | `environments/local/network` | ✅ 적용됨 | 없음 — 1번과 순서 무관, 독립적 | 지금은 특이사항 없음(§5-2). RDS/EKS가 생기면 그것들부터 먼저 지워야 함 |
| 3 | `environments/local/frontend` | ✅ 적용됨 | 1번의 `hosted_zone_id` 필요 | **가장 먼저.** zone 안에 이 모듈이 만든 레코드가 있어서(§5-1) — `force_destroy=true`라 버킷 비우기는 불필요 |
| 4 | RDS + Valkey + Secrets Manager | ⬜ 미구현 | 2번의 `private_db_subnet_ids`, `db_security_group_id` 필요 | (미구현) |
| 5 | EKS + EC2(3대) + ECR | ✅ 코드 완료, **미적용** (비용 커서 apply는 별도 확인 후) | 2번의 `private_app_subnet_ids`, `eks_security_group_id` 필요. 4번과는 서로 독립적 | 2번(network)**보다 먼저** 지워야 함(서브넷/SG를 참조 중). ECR도 `force_delete` 안 켜놔서 이미지 있으면 비우거나 옵션 추가 필요(§4 flow_logs 버킷과 같은 패턴) |
| 6 | ALB Ingress + API용 ACM | ⬜ 미구현 | 5번(로드밸런서 컨트롤러) + 1번(zone) 필요 | (미구현) |
| 7 | CloudWatch + CloudTrail | ⬜ 미구현 | 계정 레벨이라 이론상 아무 때나, 모니터링 대상(4·5번) 있어야 실익 있음 | (미구현) |

- **1·2번은 서로 의존이 없어서 순서를 바꾸거나 동시에 apply해도 무방**하다. 3번(frontend)부터는 1번이 먼저 끝나 있어야 하고, 5번(EKS)은 2번(network)의 서브넷·SG를 참조하므로 2번이 먼저 있어야 한다.
- **Destroy는 표 번호의 역순이 기본**이지만, 5번은 2번을 참조하고 있어서 **2번보다 반드시 먼저** 지워야 한다(2번을 먼저 지우면 EKS 노드가 쓰던 서브넷/SG가 없어져서 실패).
- dev/prod 환경 자체는 아직 미구축 — 계정 구조는 `docs/aws-architecture.md` §11 참고 (local은 팀원마다 다른 계정, prod는 담당자 2명이 계정 하나 공유).

## 2. 현재 적용 상태

| 환경 | 리소스 수 | 핵심 output | 상태 |
| --- | --- | --- | --- |
| `environments/bootstrap` | 5 | `route53_zone_id = Z03858108FMADVU36PUA`, `bucket_name = slash-tfstate-727646470302` | 적용됨 |
| `environments/local/network` | 38 | `vpc_id = vpc-0e99fcc8dcea839a0`, NAT 1개(`ap-northeast-2a`) | 적용됨 |
| `environments/local/frontend` | 10 | `site_url = https://local.sbsh.cloud`, `bucket_name = slash-web-local-727646470302` | 적용됨, 콘텐츠까지 배포됨 |
| `environments/dev/*` | – | – | 미구축 |
| `environments/prod/*` | – | – | 미구축 |

계정은 `727646470302`(부트캠프 공유), 리전 `ap-northeast-2`. 이 표는 스냅샷이라 실제 값이 궁금하면 각 디렉터리에서 `terraform output`으로 재확인할 것 — 아래는 마지막 갱신 시점(2026-08-04) 기준.

## 3. Apply 이력

| 날짜 | 환경 | 내용 | 비고 |
| --- | --- | --- | --- |
| 2026-08-04 | `bootstrap` | state 버킷 + `sbsh.cloud` Route53 zone 생성 | 가비아 네임서버를 output의 `route53_name_servers` 4개로 변경, 전파 확인 후 진행 |
| 2026-08-04 | `local/frontend` | S3+CloudFront+ACM+DNS 10개 생성 → `slash-web` 빌드 후 `aws s3 sync`로 콘텐츠 배포 | 첫 apply, 문제 없이 한 번에 완료 |
| 2026-08-04 | `local/network` | VPC 등 38개 생성 시도 | **1차 실패** — §4 참고. 코드 수정 후 나머지 7개 재적용해서 완료 |
| 2026-08-04 | `local/eks` | 코드 작성 + `plan` 검증(20개 리소스) | **아직 apply 안 함** — EKS 컨트롤플레인이 월 ~$75로 지금까지 중 가장 비싸서 별도 확인 후 진행 예정 |
| 2026-08-04 | `local/frontend` | `force_destroy = true`로 변경 적용 | AWS API 호출 없는 순수 Terraform state 변경 (§5-1 참고) |
| 2026-08-04 | `local/frontend` | 버킷명에 계정ID 자동 접미사 적용 (`slash-web-local` → `slash-web-local-727646470302`) | S3 버킷명 전역 유일성 때문에 버킷 교체(destroy+재생성) 발생 — 재적용 후 `aws s3 sync` + CloudFront invalidation으로 콘텐츠 복구, 팀원 신규 apply는 처음부터 이 이름으로 생성되어 영향 없음 |

## 4. 트러블슈팅 기록

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

## 5. Destroy 절차

destroy는 **apply의 역순**(frontend → network → bootstrap, §1 표의 3→2→1)으로 진행한다. 순서를 안 지키면 아래처럼 막힌다.

### 5-1. `local/frontend` — 먼저

- `force_destroy = true`로 켜뒀기 때문에(§3 마지막 항목) 버킷을 수동으로 비울 필요 없이 바로 `terraform destroy` 가능.
- **이 환경을 가장 먼저 지워야 하는 이유**: `sbsh.cloud` zone 안에 이 모듈이 만든 레코드(A/AAAA/ACM 검증용 CNAME)가 들어있다. bootstrap을 먼저 지우면 zone 자체가 없어져서 frontend destroy 시 레코드를 지우려다 "zone 없음" 에러가 난다.

```bash
cd environments/local/frontend
AWS_PROFILE=slash-local terraform plan -destroy -input=false   # 먼저 확인
AWS_PROFILE=slash-local terraform destroy -input=false
```

### 5-2. `local/network` — 다음

- 지금은 특별한 조치 불필요. 단 `flow_logs` 버킷(`slash-vpc-flow-logs-local-...`)에 `force_destroy`가 없어서, 로그가 쌓인 뒤에 지우려면 그때는 버킷을 먼저 비우거나 모듈에 `force_destroy`를 추가해야 함 (2026-08-04 기준 오브젝트 0개라 지금은 문제 없음).

```bash
cd environments/local/network
AWS_PROFILE=slash-local terraform plan -destroy -input=false
AWS_PROFILE=slash-local terraform destroy -input=false
```

### 5-3. `bootstrap` — 마지막

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
