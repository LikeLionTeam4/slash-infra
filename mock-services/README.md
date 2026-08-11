# mock-services

`slash-api`/`slash-nlu`/`slash-llm` 세 저장소에 아직 Dockerfile이 없어서, ECR push → EKS 배포
파이프라인(모듈 검증, IRSA, 이후 Karpenter/ALB/GitOps)을 실제 서비스 코드 없이도 먼저
검증하기 위한 **임시 placeholder 이미지**다.

각 서비스 README에 적힌 실제 포트를 그대로 흉내 낸다 (`/health`에 200 JSON 응답):

| 디렉터리 | 포트 | 대응 서비스 |
| --- | --- | --- |
| `slash-api/` | 8080 | Spring Boot 코어 API |
| `slash-nlu/` | 8001 | FastAPI NLU |
| `slash-llm/` | 8000 | FastAPI LLM |

## 빌드 & 로컬 실행

```bash
docker build -t slash-api-mock mock-services/slash-api
docker run --rm -p 8080:8080 slash-api-mock
curl localhost:8080/health
```

## ECR push (수동, OIDC 백엔드 Role 준비 전까지)

**태그는 `mock-<YYYYMMDD>` 형식을 쓴다** (예: `mock-20260811`) — 실제 서비스 태그(§6 규칙:
커밋 SHA, `sha-` 접두어)와 절대 겹치지 않게. `modules/eks/ecr.tf`의 lifecycle policy 3번
규칙이 `mock` 접두어 태그를 push 후 3일 지나면 자동으로 정리하므로, 검증 끝난 뒤 수동으로
지울 필요는 없다 — 공유 계정에 방치되는 이미지가 생기지 않게 하기 위한 조치.

```bash
AWS_PROFILE=slash-local aws ecr get-login-password --region ap-northeast-2 \
  | docker login --username AWS --password-stdin <account-id>.dkr.ecr.ap-northeast-2.amazonaws.com

TAG="mock-$(date +%Y%m%d)"
for svc in slash-api slash-nlu slash-llm; do
  docker build -t $svc-mock mock-services/$svc
  docker tag $svc-mock:latest <account-id>.dkr.ecr.ap-northeast-2.amazonaws.com/$svc:$TAG
  docker push <account-id>.dkr.ecr.ap-northeast-2.amazonaws.com/$svc:$TAG
done
```

`<account-id>`는 `environments/local/eks` apply 후 `ecr_repository_urls` output에서 그대로
가져온다.

## 정리 시점

각 서비스 저장소에 실제 Dockerfile + CI가 생기면 이 디렉터리는 삭제한다 — 여기 이미지는
빌드/배포 파이프라인 배선을 확인하기 위한 것이지, 실제 서비스 코드를 대신하지 않는다.
ECR에 push된 `mock-*` 태그 이미지 자체는 lifecycle policy가 3일 후 자동으로 정리하므로
별도 조치가 필요 없다.
