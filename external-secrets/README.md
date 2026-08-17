# external-secrets

External Secrets Operator(ESO) 컨트롤러 자체. `karpenter/`, ALB Controller와 같은 이유로
K8s 내부 애드온이라 ArgoCD GitOps 대상이 아니고 `helm install`로 직접 설치한다. 컨트롤러
자체에는 AWS 권한을 주지 않는다 — 각 앱(예: `slash-api`)의 `SecretStore`가 그 앱 자신의
IRSA ServiceAccount 신원으로 Secrets Manager를 읽는다(`helm/slash-api/templates/secretstore.yaml`
참고, 이슈 #23/#24). 컨트롤러 하나에 계정 전체 시크릿 읽기 권한을 몰아주지 않기 위한 선택.

## 설치 (dev)

```bash
aws eks update-kubeconfig --name slash-eks-dev --region ap-northeast-2 --profile slash-local

helm repo add external-secrets https://charts.external-secrets.io
helm repo update external-secrets

helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  --wait --timeout 5m
```

- 컨트롤러는 IRSA가 필요 없다(위 설계). `SecretStore`/`ExternalSecret` CRD는 각 서비스의
  Helm chart(`helm/slash-api/templates/`)가 ArgoCD로 배포한다 — 여기서 별도로 apply할
  매니페스트는 없다.
- 클러스터를 destroy→재apply할 때마다(카펜터/ALB Controller와 마찬가지로) 이 Helm 설치를
  반복해야 한다.

## 검증 체크리스트

- `kubectl get pods -n external-secrets` — 컨트롤러 Running 확인
- `kubectl get secretstore,externalsecret -n default` — slash-api Application sync 후 `SecretSynced` 상태 확인
- `kubectl get secret slash-api-secrets -n default -o jsonpath='{.data}'` — 키 존재만 확인(값은 출력하지 말 것)
