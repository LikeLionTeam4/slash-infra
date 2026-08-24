# helm

서비스별 Helm chart. `docs/aws-architecture.md` §9 구조를 그대로 따른다 — 서비스별
디렉터리(`slash-api/`, `slash-nlu/`, `slash-llm/`) + 환경별 values 파일
(`values-local.yaml`/`values-dev.yaml`/`values-prod.yaml`)로 분리.

`local`은 CI/CD 자동화 대상이 아니다(§11) — `values-local.yaml`은 팀원이 직접
`helm install`로 배선을 검증할 때만 쓴다. dev는 ArgoCD가 이 디렉터리를 보고
GitOps로 상시 동기화 중(§9, §11); prod는 아직 미구축.

## 지금 상태

세 서비스(`slash-api`/`slash-nlu`/`slash-llm`) 전부 실제 Dockerfile/CI가 갖춰졌고,
`values-dev.yaml`은 각 저장소 CI가 커밋 SHA 태그(`sha-*`)로 계속 갱신한다.
`values-local.yaml`도 mock 이미지에서 전환 완료(이슈 #11, 2026-08-24)했다 — local
전용 빌드 파이프라인은 없어서, dev에서 검증된 태그를 그대로 재사용한다.

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
