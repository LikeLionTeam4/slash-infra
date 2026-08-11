# argocd

ArgoCD Application manifest. `docs/aws-architecture.md` §9 설계상 GitOps 파이프라인은
dev 환경부터 적용 대상이지만, dev가 아직 미구축이라 [이슈 #10](https://github.com/LikeLionTeam4/slash-infra/issues/10)에서는
local 클러스터를 테스트베드 삼아 "Git 커밋 → ArgoCD 자동 배포" 흐름 자체를 먼저 검증한다
(ALB Controller를 local에서 먼저 검증했던 것과 같은 패턴).

## 지금 상태

`applications/*.yaml` 3개가 각각 `helm/slash-api`, `helm/slash-nlu`, `helm/slash-llm`을
`dev` 브랜치 기준으로 보고 `values-local.yaml`을 적용하도록 되어 있다 — 즉 지금은 local
클러스터 검증용 설정이다. dev 환경이 실제로 구축되면 `targetRevision`/`valueFiles`를
`values-dev.yaml` 기준으로 바꾸고, 이 Application들이 가리키는 클러스터도 dev EKS로
옮겨야 한다.

## ArgoCD 설치 (local 검증)

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
