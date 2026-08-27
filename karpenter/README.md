# karpenter

Karpenter NodePool/EC2NodeClass 매니페스트. `argocd/`와 같은 이유로 K8s 내부 리소스라
GitOps 대상은 아니고 `kubectl apply`로 직접 적용한다 — Helm 설치(컨트롤러 자체)와
NodePool/EC2NodeClass(CRD)는 별개다.

## 설치 (dev)

IRSA Role(`slash-karpenter-controller-dev`)은 `modules/eks/karpenter.tf`로 이미 준비돼 있다.

```bash
aws eks update-kubeconfig --name slash-eks-dev --region ap-northeast-2 --profile slash-local

helm install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version "1.10.0" \
  --namespace kube-system \
  --set settings.clusterName=slash-eks-dev \
  --set settings.interruptionQueue="" \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=arn:aws:iam::061039804626:role/slash-karpenter-controller-dev \
  --wait --timeout 5m

kubectl apply -f karpenter/dev/nodepool.yaml
```

- **버전 고정 이유**: 기본값(1.1.1 등 오래된 버전)은 EKS 1.36과 `panic: karpenter version is not compatible with K8s version`으로 즉시 죽는다(2026-08-12 확인) — 반드시 클러스터의 K8s 버전과 호환되는 Karpenter 버전을 먼저 확인하고 설치할 것. `docker manifest inspect public.ecr.aws/karpenter/karpenter:<version>`로 태그 존재 여부를 미리 확인할 수 있다.
- `settings.interruptionQueue`를 비워둔 이유: 지금은 온디맨드만 쓰고(spot 미사용) SQS 인터럽션 큐를 별도로 안 만들었다 — spot을 실제로 쓰기 시작하면 그때 큐를 추가하고 이 값을 채워야 한다.

## 검증 이력 (2026-08-12)

- 리소스 요청이 큰 테스트 파드(cpu 1500m × 4)를 배포 → 기존 3개 노드에 안 들어가는 2개가 Pending → **24초 만에 새 노드 프로비저닝**, 전부 스케줄링 확인
- 테스트 워크로드 삭제 → **145초 뒤 추가 노드 자동 정리**(consolidation, `consolidateAfter: 1m`) 확인
- `docs/operations-log.md` §8 참고
