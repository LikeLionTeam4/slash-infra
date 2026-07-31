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
