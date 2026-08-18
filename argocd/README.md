# argocd

ArgoCD Application manifest. `applications/*.yaml`은 local 클러스터 검증용(이슈 #10,
`values-local.yaml`), `applications-dev/*.yaml`이 2026-08-18부터 상시 운영 중인 실제
dev 환경용(`values-dev.yaml`, 이슈 #24)이다.

## 웹훅 대신 폴링 주기 단축 (2026-08-18, 이슈 #15)

**즉시 sync를 위한 GitHub webhook은 도입하지 않기로 결정.** ArgoCD 서버를 인터넷에
노출해야 하는데(새 서브도메인+ACM+Ingress), 이 계정이 다른 부트캠프 팀과 공유하는
계정이라 새 공개 노출 지점을 늘리는 리스크가 지금 팀 규모에서 얻는 이득(3분→수초)보다
크다고 판단했다. 대신 `timeout.reconciliation`을 기본 180s → 60s로 낮춰 지연을
줄였다 — 설정 한 줄로 되돌리기도 쉽고 새 컴포넌트/노출 지점이 없다. 실제로 근접
즉시성이 필요해지면(트래픽·팀 규모가 커지면) 그때 webhook을 재검토한다.

## ArgoCD 설치 (dev)

```bash
aws eks update-kubeconfig --name slash-eks-dev --region ap-northeast-2 --profile slash-local

helm repo add argo https://argoproj.github.io/argo-helm
helm repo update argo
kubectl create namespace argocd
helm install argocd argo/argo-cd --namespace argocd --version 7.7.11 \
  --set configs.cm."timeout\.reconciliation"=60s \
  --wait --timeout 5m

kubectl apply -f argocd/applications-dev/
```

## ArgoCD 설치 (local 검증용, 참고)

```bash
aws eks update-kubeconfig --name slash-eks-local --region ap-northeast-2 --profile slash-local

helm repo add argo https://argoproj.github.io/argo-helm
helm repo update argo
kubectl create namespace argocd
helm install argocd argo/argo-cd --namespace argocd --version 7.7.11 --wait --timeout 5m

kubectl apply -f argocd/applications/
```

## ArgoCD UI 접속 (포트포워딩)

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:443
# admin 비밀번호
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```
