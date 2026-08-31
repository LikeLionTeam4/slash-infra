# reloader

[stakater/reloader](https://github.com/stakater/Reloader) 컨트롤러 자체. `karpenter/`,
`external-secrets/`와 같은 이유로 K8s 내부 애드온이라 ArgoCD GitOps 대상이 아니고
`helm install`로 직접 설치한다.

## 왜 필요한가

External Secrets Operator가 `refreshInterval`마다 Secrets Manager 값을 k8s Secret으로
동기화해도, **이미 떠 있는 파드는 그 Secret을 다시 읽지 않는다**(k8s가 Pod 생성 시점에
환경변수를 고정하기 때문). RDS 관리형 비밀번호 자동 로테이션 때 이 문제로 파드가 옛
비밀번호에 고착되는 사고가 두 번 있었다(`docs/operations-log.md` §22, §35 — 특히 §35는
평소엔 기존 커넥션 풀을 재사용해 멀쩡해 보이다가 부하로 풀이 소진되는 순간에만 터지는
형태라 `kubectl get pods`만으로는 알아채기 어려웠다). 관련 논의: 이슈 #80.

Reloader는 감시 대상 Secret/ConfigMap의 내용이 바뀌면 그걸 참조하는 Deployment를
자동으로 롤링 재시작시켜, 이 문제를 구조적으로 없앤다.

## 설치 (dev)

```bash
aws eks update-kubeconfig --name slash-eks-dev --region ap-northeast-2 --profile slash-local

helm repo add stakater https://stakater.github.io/stakater-charts
helm repo update stakater

helm install reloader stakater/reloader \
  --namespace kube-system \
  --wait --timeout 5m
```

- 클러스터를 destroy→재apply할 때마다(카펜터/ALB Controller와 마찬가지로) 이 Helm 설치를
  반복해야 한다.
- 컨트롤러 자체에는 별도 IAM 권한이 필요 없다(클러스터 내부에서 Secret/ConfigMap
  변경 이벤트만 watch).

## 사용법

감시 대상 Deployment에 아래 annotation을 달아두면 끝 — Reloader가 알아서 감지한다.

```yaml
metadata:
  annotations:
    secret.reloader.stakater.com/reload: "<secret-이름>"
```

`slash-api`는 `helm/slash-api/templates/deployment.yaml`에
`secret.reloader.stakater.com/reload: "<release>-secrets"`로 이미 달아뒀다
(ExternalSecret이 만드는 `DB_USERNAME`/`DB_PASSWORD`/`VALKEY_AUTH_TOKEN`을 담은 그
Secret). `slash-nlu`는 참조하는 Secret이 없어 annotation이 필요 없다.

## 검증 체크리스트

- `kubectl get pods -n kube-system -l app=reloader-reloader` — 컨트롤러 Running 확인
- `kubectl logs -n kube-system -l app=reloader-reloader` — 대상 Secret 변경 시
  `Changes Detected in secret ... Updating deployment ...` 로그로 실제 롤링 재시작
  트리거 확인
- Secret 값을 바꾼 뒤(`kubectl annotate externalsecret ... force-sync=... --overwrite`로
  강제 동기화) `kubectl rollout history deployment/slash-api`에 새 리비전이 자동으로
  추가되는지 확인 — 이제 이 단계를 사람이 수동으로 `kubectl rollout restart` 안 해도 된다.
