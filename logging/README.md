# logging

`aws-for-fluent-bit`(AWS 공식 Fluent Bit 배포판) — slash-api/slash-nlu 파드의
stdout/stderr를 CloudWatch Logs로 전송한다. `karpenter/`, ALB Controller와 같은 이유로
K8s 내부 애드온이라 ArgoCD GitOps 대상이 아니고 `helm install`로 직접 설치한다.

**배경**: 지금까지 파드 로그는 `kubectl logs`로만 볼 수 있어서 파드가 재시작/스케일다운되면
그 시점 로그가 사라졌다(이슈 #44). 이 설치로 CloudWatch Logs에 로그가 남아 파드 생사와
무관하게 조회 가능해진다. 지표(CPU/메모리, Container Insights vs Prometheus/Grafana)는
별개 이슈(#47)로 이번 설치 범위 밖.

## 설치 (dev)

IRSA Role(`slash-fluent-bit-dev`)과 로그 그룹(`/eks/slash-eks-dev/application`, 보존기간
`log_retention_days`)은 `modules/eks/fluent_bit_irsa.tf`/`logging.tf`로 이미 준비돼 있다
(`terraform output fluent_bit_role_arn`으로 확인).

```bash
aws eks update-kubeconfig --name slash-eks-dev --region ap-northeast-2 --profile slash-local

helm repo add eks https://aws.github.io/eks-charts
helm repo update eks

helm install aws-for-fluent-bit eks/aws-for-fluent-bit \
  --namespace amazon-cloudwatch --create-namespace \
  --set serviceAccount.name=fluent-bit \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=<terraform output fluent_bit_role_arn> \
  --set cloudWatchLogs.region=ap-northeast-2 \
  --set cloudWatchLogs.logGroupName=/eks/slash-eks-dev/application \
  --set cloudWatchLogs.autoCreateGroup=false \
  --wait --timeout 5m
```

- **`cloudWatchLogs.*`를 쓰는 이유(`cloudWatch.*` 아님)**: 차트 values.yaml에 출력 블록이 두
  개 있다 — `cloudWatch`(레거시 `cloudwatch` 플러그인, 기본 `enabled: false`)와
  `cloudWatchLogs`(최신 `cloudwatch_logs` 플러그인, 기본 `enabled: true`). 설치 전
  `helm show values eks/aws-for-fluent-bit`로 반드시 실제 키를 확인할 것 — 버전에 따라
  달라질 수 있다.

- **`serviceAccount.name=fluent-bit` + `--namespace amazon-cloudwatch` 고정 이유**: IRSA Role의
  신뢰 관계(`fluent_bit_irsa.tf`)가 `system:serviceaccount:amazon-cloudwatch:fluent-bit`로
  못박혀 있다 — 네임스페이스나 ServiceAccount 이름을 바꾸면 `AssumeRoleWithWebIdentity`가
  실패(`AccessDenied`)한다.
- **`cloudWatch.autoCreateGroup=false` 이유**: 로그 그룹은 Terraform이 보존기간을 명시해
  이미 만들어뒀다(`modules/eks/logging.tf`) — 차트가 그룹을 자동 생성하게 두면 보존기간이
  무기한("Never expire")으로 되돌아갈 수 있다(`eks_cluster` 로그 그룹과 동일한 함정,
  logging.tf 주석 참고). 이 옵션을 켜두려면 Fluent Bit IAM 정책에
  `logs:CreateLogGroup`/`PutRetentionPolicy`를 추가해야 하는데, 지금은 일부러 안 줬다.
- 클러스터를 destroy→재apply할 때마다(Karpenter/ALB Controller/ESO와 마찬가지로) 이 Helm
  설치를 반복해야 한다.

## 검증 체크리스트

- `kubectl get pods -n amazon-cloudwatch` — 노드 수만큼 Fluent Bit DaemonSet 파드 Running 확인
- `aws logs tail /eks/slash-eks-dev/application --follow --profile slash-dev` — slash-api/slash-nlu
  로그가 실시간으로 들어오는지, `kubectl logs`로 보이는 내용과 일치하는지 확인
- 파드 하나를 의도적으로 재시작(`kubectl delete pod <slash-api-pod>`)시킨 뒤, 재시작 **전**
  로그가 CloudWatch에 그대로 남아있는지 확인 — 이 설치의 핵심 목적
- 1~2일 실사용 트래픽 기준으로 CloudWatch 콘솔에서 로그 그룹의 `IncomingBytes` 지표를 확인해
  실제 수집량을 산정하고, 필요하면 `log_retention_days`를 조정한다(`docs/operations-log.md`에
  실측 결과 기록)
