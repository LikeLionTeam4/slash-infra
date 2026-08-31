# 장애 대응 테스트 (Resilience / Game Day)

`docs/aws-architecture.md`가 "무엇을 왜 이렇게 설계했는가", `docs/operations-log.md`가 "실제로 뭘 적용했는가"를 다룬다면, 이 문서는 **"실제 장애 상황에서 우리 인프라가 감지·복구를 제대로 하는지 어떻게 확인하는가"**를 다룬다. 카오스 엔지니어링(chaos engineering)에서 흔히 "게임 데이(game day)"라고 부르는, 의도적으로 장애를 주입해보는 훈련의 카탈로그다.

**이 문서 = 테스트 방법 카탈로그(재사용 가능한 참고 자료).**
**실제로 테스트를 실행한 기록(언제, 누가, 무슨 일이 있었는지) = `docs/operations-log.md`에 새 `§N`으로 추가** — 기존 "검증 라운드" 관행(§7 로컬 배포 시나리오 5종, §16 Ollama keep_alive 검증 등)과 동일한 형식을 그대로 쓴다. §4 하단에 기록 템플릿이 있다.

계기: [이슈 #56](https://github.com/LikeLionTeam4/slash-infra/issues/56)(공유 계정 다른 팀이 실수로 NAT Gateway 삭제) — 실제 장애를 겪고 나서야 "우리가 이런 상황에 대비돼 있는지" 알게 됐다. 다음부터는 겪기 전에 스스로 검증해보자는 취지.

## 1. 원칙

- **테스트 전에 "무엇이 성공인지" 먼저 정의한다.** 예: "다운타임 2분 이내", "알림이 5분 이내 도착", "수동 개입 없이 자동 복구". 기준 없이 실행하면 결과를 봐도 잘 된 건지 판단할 수 없다.
- **공유 계정이므로 사전 공지 필수.** `061039804626`은 여러 팀이 같이 쓰는 부트캠프 계정 — dev 환경 자체를 흔드는 테스트(EKS 노드 종료, RDS failover 등)는 팀 채널에 시간대를 먼저 알린다(`docs/resource-ownership.md` 참고).
- **가능하면 AWS 공식 지원 방법을 먼저 쓴다.** `aws rds reboot-db-instance --force-failover`처럼 AWS가 실제로 지원하는 장애 시뮬레이션 API가 있으면, 리소스를 직접 지우는 것보다 안전하고 결과 해석도 쉽다.
- **결과는 반드시 기록한다.** 안 됐어도(오히려 안 됐을 때 더) 기록 가치가 크다 — §4 템플릿대로 `operations-log.md`에 남긴다.
- **관측 채널을 테스트 시작 전에 열어둔다.** `kubectl logs -f`, CloudWatch 대시보드(`terraform output dashboard_url`, `environments/dev/observability`), SNS 이메일함을 테스트 시작 전부터 띄워두고 타임스탬프를 기록해야 "몇 분 걸렸는지"를 나중에 정확히 잴 수 있다.

## 2. 테스트 카탈로그

### ① 안전 — AWS 공식 지원 방법

| 테스트 | 목적 | 실행 방법 | 성공 기준 | 소요 시간 |
| --- | --- | --- | --- | --- |
| RDS Multi-AZ 장애조치 | 대기 인스턴스로 전환 시 앱이 재연결하는지 | `aws rds reboot-db-instance --db-instance-identifier slash-rds-dev --force-failover` | 앱이 수동 재시작 없이 다시 응답, RDS CPU/연결 알람이 과잉 반응하지 않음 | 실제 failover 60~120초 |
| EKS 노드 장애 복구 | Karpenter가 대체 노드를 자동으로 띄우는지 | 노드 하나 `kubectl cordon` + `kubectl drain --ignore-daemonsets`, 또는 해당 EC2 인스턴스를 `aws ec2 terminate-instances`로 직접 종료 | 파드가 다른/새 노드로 재스케줄, ALB가 그 사이 5xx를 과도하게 내지 않음 | 수 분(새 노드 프로비저닝 포함) |
| 부하테스트 / HPA 오토스케일링 검증 | CPU 임계치(70%)에서 HPA가 실제로 스케일아웃/인 하는지, 그 사이 ALB 5xx가 튀지 않는지 | `k6`/`hey` 등으로 `api.dev.sbsh.cloud`에 점증 부하(ramping VUs) 실행. 파드 CPU 지표는 기본적으로 CloudWatch에 없으므로(Container Insights 미도입, 이슈 #47) 테스트 기간만 `aws eks create-addon --addon-name amazon-cloudwatch-observability`로 Container Insights를 임시로 붙였다가 끝나면 `delete-addon`으로 제거 | HPA가 replica를 늘렸다가 부하 종료 후 되돌림, 그 사이 ALB 5xx 알람 미발생 | 램프업+관찰 수 분~수십 분 |

### ② 재현 — 실제로 겪었던 장애를 통제된 시간에 재현

| 테스트 | 목적 | 실행 방법 | 성공 기준 | 참고 |
| --- | --- | --- | --- | --- |
| NAT Gateway 삭제 | SNS 알림이 실제로 오는지, 복구 절차가 먹히는지 | `aws ec2 delete-nat-gateway --nat-gateway-id <id>` (2개 중 1개만 먼저) | 알림 이메일 5분 이내 도착, `docs/operations-log.md` §19 절차대로 `terraform apply`로 복구 | slash-infra#56/#57 |
| Valkey 연결 끊김 | "Valkey 못 붙으면 앱이 아예 안 뜬다" 문제가 재발하지 않는지 | `aws ec2 revoke-security-group-ingress`로 EKS→Valkey 포트(6379) 일시 차단, 확인 후 `authorize`로 원복 | 앱이 예상된 방식으로 에러 처리(크래시 루프 아님), Valkey 알람 반응, 복구 후 정상화 | slash-api#36(해결됨) 재검증 |
| ArgoCD self-heal | 클러스터 직접 변경을 자동으로 되돌리는지 | `kubectl scale deploy slash-api --replicas=4` 처럼 git과 다른 상태로 수동 변경 | 수 초~수 분 내 selfHeal이 git 상태로 되돌림 | 이전에 ~3초 만에 확인된 적 있음(재검증 성격) |
| Secrets 유출 대응(수동 로테이션) | 시크릿(예: Valkey AUTH 토큰)이 유출됐다고 가정했을 때 무효화→재발급→파드 반영까지 절차가 실제로 동작하는지 | `terraform apply -replace=<random_password 주소>`로 강제 재생성 → Secrets Manager 반영 확인 → `kubectl annotate externalsecret <name> force-sync=$(date +%s) --overwrite`로 강제 동기화 → 이미 떠 있는 파드는 env가 고정돼 있어 재연결 실패 가능(§22와 같은 근본원인) → `kubectl rollout restart deployment/<name>` | 옛 토큰으로는 더 이상 연결 안 됨(유출 무효화 확인), 재시작 후 정상 재연결 | §22(RDS 버전 동일 문제) 관련, Reloader 등 자동화 미도입 상태라 수동 rollout restart가 현재의 유일한 복구 수단 |

### ③ 침투적 — 사전 조율 필수

| 테스트 | 목적 | 실행 방법 | 성공 기준 | 주의 |
| --- | --- | --- | --- | --- |
| ALB 헬스체크 실패 | 타깃 제외/ALB 5xx 알람이 실제로 도는지 | slash-api 헬스체크 엔드포인트를 일시적으로 깨뜨림(예: readiness probe 실패하게) | ALB가 해당 타깃을 `unhealthy`로 빼고 나머지로 트래픽 유지, ALB 5xx 알람 반응 | 실제 사용자 트래픽에 영향 가능 — 테스트 대상 시간대 서비스 사용 여부 확인 |
| AZ 단위 장애 시뮬레이션 | 한 AZ 전체가 죽어도 나머지로 버티는지 | AWS Fault Injection Simulator(FIS)로 특정 AZ의 서브넷/NAT 트래픽을 차단하는 실험 템플릿 구성 | 반대편 AZ(2a 또는 2c)만으로 서비스 유지 | 준비(FIS 실험 템플릿 작성)가 필요해 가장 나중 |
| CloudFront/S3 오리진 차단 | 오리진(S3)에 접근 못 하면 어떻게 실패하는지, 캐시된 자산은 계속 서빙되는지 | S3 버킷 정책에 CloudFront OAC principal 대상 임시 `Deny` 문 추가(사전에 `aws s3api get-bucket-policy`로 원본 백업) → `dev.sbsh.cloud` 요청 확인 → 즉시 원복. CloudFront 배포 자체를 비활성화하는 방법은 전파에 5~15분 걸려 비실용적이라 제외 | 캐시 hit 경로는 계속 정상 응답, 캐시 miss 경로는 502/504로 명확히 실패(무한 대기 아님), 정책 원복 즉시 정상화 | 현재 오리진은 S3 단일 구성이라 페일오버 자체가 없음 — 이 테스트는 "복구 확인"이 아니라 "장애 시 어떻게 보이는지"를 확인하는 성격 |

### ④ 외부 서비스 의존성 장애 — 실행 불가, 런북 전용

이 카테고리는 실제로 장애를 주입할 수 없는(GitHub 등 외부 SaaS를 우리가 끌 수 없는) 시나리오다. 대신 "그 상황이 오면 무엇을 하는가"를 런북으로 정리하고, 런북에 나온 수동 절차 자체는 평상시에 리허설해서 실제로 동작하는지 확인한다.

| 시나리오 | 실제 영향 | 대응 런북 | 리허설 방법 |
| --- | --- | --- | --- |
| GitHub(Actions/저장소) 전체 장애 | 각 앱 저장소의 GitHub Actions가 안 돌아 ECR push/CloudFront invalidate 신규 배포가 막힐 뿐 아니라, **ArgoCD도 slash-infra 저장소(GitHub)를 폴링해서 GitOps 동기화하는 구조라 selfHeal/신규 sync 자체가 막힌다** | 1) ArgoCD auto-sync를 임시로 끈다(`argocd app set <app> --sync-policy none`) 2) 이미 ECR에 있는 이미지 태그로 `kubectl set image deployment/<name> <container>=<ecr-image>:<tag>`로 수동 배포 3) GitHub 복구 후 `--sync-policy automated`로 되돌려 git 상태로 재수렴 | dev에서 실제로 auto-sync를 끄고 `kubectl set image`가 유지되는지, 이후 auto-sync를 켰을 때 selfHeal이 git 버전으로 되돌리는지 리허설 가능(§30) |

## 3. 사전 체크리스트

테스트 실행 전에 아래를 확인한다.

- [ ] 팀 채널에 테스트 시간대·대상 공지
- [ ] 이 테스트의 "성공 기준" 명확히 적어둠(§1 원칙)
- [ ] 복구 절차 위치 확인(`docs/operations-log.md`에서 관련 §번호 찾아둠)
- [ ] CloudWatch 대시보드 / `kubectl logs -f` / SNS 수신 메일함 열어둠
- [ ] 테스트 시작 시각 기록(타임라인 작성용)

## 4. 결과 기록 템플릿

테스트 실행 후 `docs/operations-log.md`에 새 `## N. <테스트 이름> 게임 데이 (2026-MM-DD)` 절을 추가하고 아래 형식으로 적는다(기존 §7/§16과 동일한 톤 — 성공했어도 그 과정을 구체적으로).

```markdown
## N. <테스트 이름> 게임 데이 (2026-MM-DD)

**시나리오**: 카탈로그 §2의 어떤 테스트를 실행했는지, 왜 지금 하는지.

**성공 기준**: 테스트 전에 정의한 기준 그대로.

**타임라인**:
- HH:MM — 장애 주입(실행한 명령 그대로)
- HH:MM — 첫 이상 징후 관측(로그/대시보드에서 뭘 봤는지)
- HH:MM — 알림 도착(어떤 채널로, 몇 분 걸렸는지)
- HH:MM — 복구 조치 시작
- HH:MM — 정상화 확인

**결과**: 성공 기준 충족 여부 + 실제 걸린 시간.

**발견한 문제** (있다면): 원인/조치/교훈 — 문제였으면 후속 이슈 번호 남기고, 코드/설정을 고쳤으면 그 커밋도.

**다음에 다시 할 때 참고할 것**: 이번에 겪은 시행착오(예: 명령어 오타, 권한 부족 등).
```

## 5. 테스트 이력 (요약 인덱스)

실제 실행 기록은 `operations-log.md`에 있고, 여기는 빠르게 찾기 위한 인덱스만 유지한다. 새로 테스트를 실행하면 이 표에 한 줄 추가.

| 날짜 | 테스트 | 결과 | 상세 기록 |
| --- | --- | --- | --- |
| 2026-08-30 | RDS Multi-AZ 장애조치 | 성공 (재연결 자동, 알람 정상) | operations-log.md §27 |
| 2026-08-30 | EKS 노드 장애 복구 | 성공 (다운타임 없음, PDB 부재 리스크는 발견) | operations-log.md §28 |
| 2026-08-30 | CloudFront/S3 오리진 차단 | 성공 (36초 내 원복, 오리진 페일오버 부재 재확인) | operations-log.md §29 |
| 2026-08-30 | GitHub 장애 대응 리허설 | 성공 (수동 배포 유지, selfHeal 복구 7초) | operations-log.md §30 |
| 2026-08-30 | Secrets 유출 대응 리허설 (Valkey) | 부분 성공 (새 토큰 검증됨, 옛 토큰 무효화는 미검증) | operations-log.md §31 |
| 2026-08-31 | 부하테스트 + Container Insights | 부분 충족 (5xx 0건, 스케일아웃은 미확인/재검증 필요, Container Insights IAM 갭 발견 → 이슈 #47) | operations-log.md §32 |
