# infra

Slash AWS 인프라. 역할별 재사용 모듈(`modules/`)과 이를 조합하는 환경(`environments/`)으로 나눈다.

```
modules/
  frontend-hosting/   # S3 + CloudFront + ACM + Route53 — 정적 프론트엔드 호스팅
environments/
  dev/
    frontend/          # frontend-hosting 모듈을 dev 값으로 조합
```

환경 디렉터리마다 별도 state를 가지므로, 전체를 한 번에 적용할 수도 있고(`terraform apply`)
바뀐 모듈만 골라 적용할 수도 있다(`-target` 또는 필요한 환경 디렉터리에서만 apply).

## 사용법 (예: environments/dev/frontend)

```
cd environments/dev/frontend
cp terraform.tfvars.example terraform.tfvars   # 실제 값으로 채우기
terraform init
terraform plan
```

## 관련 저장소

| 저장소 | 역할 |
|---|---|
| [slash-web](https://github.com/LikeLionTeam4/slash-web) | 웹 클라이언트 — React·Vite UI, S3/CloudFront 배포 |
| [slash-api](https://github.com/LikeLionTeam4/slash-api) | 코어 API — 인증, 작업 관리, 실행 위치 결정, DB 연동 |
| [slash-nlu](https://github.com/LikeLionTeam4/slash-nlu) | 자연어 분석 — slash 명령 파싱, 규칙·Kiwi 의도 분류, 인자 추출 |
| [slash-llm](https://github.com/LikeLionTeam4/slash-llm) | LLM 서비스 — Gemma 추론, 요약·대화 생성 |
| [slash-agent](https://github.com/LikeLionTeam4/slash-agent) | 로컬 에이전트 — PC 파일 검색, 상태 조회, 로컬 AI 실행·결과 전달 |
| **slash-infra** (현재) | 인프라 — Terraform(AWS), Helm·ArgoCD 배포 |
| [slash-docs](https://github.com/LikeLionTeam4/slash-docs) | 프로젝트 문서 — 아키텍처, API 계약, ERD, 회의록 |
