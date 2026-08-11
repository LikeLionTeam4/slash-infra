# helm

서비스별 Helm chart. `docs/aws-architecture.md` §9 구조를 그대로 따른다 — 서비스별
디렉터리(`slash-api/`, `slash-nlu/`, `slash-llm/`) + 환경별 values 파일
(`values-local.yaml`/`values-dev.yaml`/`values-prod.yaml`)로 분리.

`local`은 CI/CD 자동화 대상이 아니다(§11) — `values-local.yaml`은 팀원이 직접
`helm install`로 배선을 검증할 때만 쓴다. dev/prod는 ArgoCD가 이 디렉터리를 보고
GitOps로 동기화할 예정(§9, 아직 미구축).

## 지금 상태

실제 서비스 저장소(`slash-api`/`slash-nlu`/`slash-llm`)에 아직 Dockerfile이 없어서,
`values-local.yaml`은 이 저장소의 `mock-services/`가 ECR에 push한 mock 이미지
(`mock-20260811-amd64`)를 기본값으로 쓴다. 실제 Dockerfile/CI가 생기면 이 값을
지우고, `values-dev.yaml`/`values-prod.yaml`처럼 CI가 커밋 SHA 태그로 채우는 방식으로
바꾼다.

## 로컬에서 검증

```bash
aws eks update-kubeconfig --name slash-eks-local --region ap-northeast-2 --profile slash-local

helm install slash-api helm/slash-api -f helm/slash-api/values-local.yaml
helm install slash-nlu helm/slash-nlu -f helm/slash-nlu/values-local.yaml
helm install slash-llm helm/slash-llm -f helm/slash-llm/values-local.yaml
```

## 아직 안 채운 값

- `serviceAccount.roleArn` — RDS/Secrets Manager 접근용 IRSA Role ARN. local은 RDS를
  안 띄우므로 비워둠, dev/prod는 `environments/<env>/eks` apply 후 채운다.
- `slash-llm`의 `nodeSelector`/`tolerations` — GPU 노드그룹이 아직 없다(§5, §13 TODO).
  준비되면 `values-dev.yaml`/`values-prod.yaml`에 채운다.
- `values-dev.yaml`/`values-prod.yaml`의 `image.tag`, `ingress.host` — `environments/dev`,
  `environments/prod` 자체가 아직 미구축이라 실제 값은 그때 채운다.
