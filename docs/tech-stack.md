# 기술 스택 아키텍처

`docs/aws-architecture.md`가 AWS 리소스 토폴로지를, `docs/user-flow.md`가 요청 단위 흐름을
다룬다면, 이 문서는 "각 컴포넌트가 실제로 어떤 언어/프레임워크/라이브러리로 만들어졌는가"를
정리한다. 기준: 각 서비스 저장소(`slash-web`/`slash-api`/`slash-nlu`/`slash-llm`/`slash-runner`, 구 `slash-agent`)를
로컬 clone에서 직접 확인(2026-08-19) — `package.json`/`build.gradle.kts`/`requirements*.txt`/
`*.egg-info` 기준.

```mermaid
flowchart TB
    subgraph CLIENT["클라이언트"]
        WEB["slash-web\nReact 19 + TypeScript + Vite 8\nTailwindCSS 4, react-router 8\noidc-client-ts (Cognito PKCE)"]
        AGENT["slash-runner (사용자 PC, 로컬)\nPython\nwebsockets(WSS 클라이언트), pystray + pywebview(트레이/UI)\nwatchdog(파일감시), keyring, cryptography\nPyInstaller 패키징"]
    end

    subgraph APP["애플리케이션 레이어 (EKS, ArgoCD GitOps)"]
        API["slash-api\nJava 21 + Spring Boot 3.5.9\nSecurity + OAuth2 Resource Server(JWT 검증)\nSpring WebSocket(사용자·에이전트 WSS)\nSpring Data Redis, jOOQ + Flyway"]
        NLU["slash-nlu\nPython + FastAPI + Pydantic\nkiwipiepy(한국어 형태소 분석), uvicorn"]
        LLM["slash-llm\nPython + FastAPI + Pydantic\nhttpx(Ollama 클라이언트), uvicorn"]
    end

    subgraph AI["AI 런타임 (EC2, EKS 밖)"]
        OLLAMA["Ollama\ngemma3:4b"]
    end

    subgraph DATA["데이터 계층 (RDS/ElastiCache)"]
        PG[("PostgreSQL 16\nFlyway 마이그레이션\njOOQ 코드생성")]
        VALKEY[("Valkey\nAUTH+TLS")]
    end

    COGNITO["Cognito\nEMAIL_OTP + JWT(OAuth2 code+PKCE)"]

    subgraph PLATFORM["플랫폼 / IaC / CI-CD"]
        TF["Terraform\n(modules/ + environments/)"]
        HELM_ARGO["Helm 차트 → ArgoCD(GitOps)"]
        GHA["GitHub Actions\n(OIDC → AWS, 빌드·ECR push)"]
        ECR_["ECR"]
    end

    WEB -->|"HTTPS + Bearer JWT"| API
    WEB <-->|Hosted UI 리다이렉트| COGNITO
    AGENT <-->|"WSS 상시연결"| API
    API --> NLU
    API --> LLM
    API --> PG
    API --> VALKEY
    API -.->|JWT 검증| COGNITO
    LLM --> OLLAMA
    API -.->|"async_jobs/outbox 스키마 설계됨\n🔲 SQS 큐 자체는 미구축"| SQS["SQS (미구축)"]

    GHA -->|"sha- 태그 push"| ECR_
    GHA -->|"values-dev.yaml 커밋"| HELM_ARGO
    HELM_ARGO --> APP
    TF -.->|프로비저닝| APP
    TF -.-> DATA
    TF -.-> COGNITO
    TF -.-> AI
```

## 서비스별 스택

| 서비스 | 언어/런타임 | 핵심 프레임워크·라이브러리 | 배포 형태 |
| --- | --- | --- | --- |
| `slash-web` | TypeScript, Node(빌드타임) | React 19, Vite 8, TailwindCSS 4, react-router 8, `oidc-client-ts` | 정적 빌드 → S3 + CloudFront (`modules/frontend-hosting`) |
| `slash-api` | Java 21 | Spring Boot 3.5.9 (Web/Validation/Actuator/Security/OAuth2 Resource Server/WebSocket/Data Redis), jOOQ, Flyway | 컨테이너 → EKS (Helm, ArgoCD) |
| `slash-nlu` | Python | FastAPI, Pydantic, `kiwipiepy`, uvicorn | 컨테이너 → EKS (Helm, ArgoCD) |
| `slash-llm` | Python | FastAPI, Pydantic, `httpx`, uvicorn | 컨테이너 → EKS (Helm, ArgoCD) |
| `slash-runner`(구 `slash-agent`) | Python | `websockets`, `pystray`, `pywebview`, `watchdog`, `keyring`, `cryptography` | PyInstaller 패키징, 사용자 PC에서 로컬 실행(AWS 범위 밖) |
| Ollama | — | `gemma3:4b` | EC2(`g4dn.xlarge`, GPU) 단독 설치, EKS 밖 |

## 확인된 사실 vs 설계뿐인 것

- **SQS는 아직 인프라에 없다.** `slash-api`의 `V006__create_async_jobs_outbox.sql` 마이그레이션
  주석("비동기 작업은 SQS가 담당한다")과 `async_jobs`/`outbox_events` 테이블 스키마는 SQS 발행을
  전제로 설계돼 있지만, `slash-infra` 저장소 전체를 검색해도 SQS 관련 Terraform 리소스는
  없다(`karpenter/README.md`의 SQS 언급은 스팟 인터럽션 큐 얘기로 무관). 즉 **outbox 패턴은
  코드/스키마 레벨로 준비돼 있고, 실제 큐 프로비저닝은 아직 이 저장소의 TODO로 남아있지 않다** —
  다음에 `slash-api` 쪽에서 이 경로를 실제로 쓰기 시작하면 `modules/`에 SQS(+ DLQ) 모듈이
  새로 필요하다는 뜻. `docs/user-flow.md` §2에서 확인한 자유입력 흐름은 이 outbox 경로가 아니라
  `slash-api → slash-nlu → slash-llm` 동기 호출이었다 — 두 경로가 공존하는지, outbox가 어떤
  작업 유형(`job_type`)에만 쓰이는지는 `slash-api` 쪽에 후속 확인 필요.
- `slash-web`의 인증은 `oidc-client-ts`로 브라우저가 Cognito와 직접 PKCE 코드 교환을 하는
  구조로 확인됨(§1 `docs/user-flow.md`에 남겼던 추정이 이 라이브러리 존재로 뒷받침됨).
- `slash-api`가 agent와 주고받는 실시간 채널은 Spring WebSocket 의존성으로 실제 구현이
  뒷받침된다 — 다만 페어링된 agent에게 서버가 작업을 실제로 위임하는 흐름 자체는
  `docs/user-flow.md` §3에서 이미 밝혔듯 이번 확인 범위에서 재현되지 않았다.
