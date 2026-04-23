# kagent + agentgateway 운영 메모

이 문서는 `~/workspace/my-cluster` remote 작업트리에 반영된 `kagent`, `kmcp`, `agentgateway`, `Authelia` 구성을 압축해서 설명한다.

## 현재 상태

- `kagent`는 `0.9.0`, `kmcp`는 `0.2.8` 기준으로 설치되어 있다.
- `kagent`는 `default` 프로필 기반이지만 현재 클러스터에서는 `argo-rollouts`, `cilium` agent를 비활성화하고 관련 tool provider도 values에서 제외한다.
- `kmcp`는 `kagent` namespace에 별도 설치되어 있으며 `MCPServer` CRD와 컨트롤러가 정상 동작한다.
- `agentgateway`는 `kagent`의 A2A/MCP 앞단 프록시로 설치되어 있다.
- `kagent` namespace는 ambient + 전용 waypoint(`waypoint-kagent`)가 적용되어 있다.
- `Authelia`는 `api.anyflow.net/auth` 경로로 공통 로그인 포털을 제공한다.

## 외부 엔드포인트

- `https://kagent.anyflow.net/` -> `kagent` UI (로그인 필요)
- `https://kagent.anyflow.net/api/a2a/...` -> `kagent` A2A (비보호)
- `https://kagent.anyflow.net/mcp` -> `kagent` MCP via `agentgateway` (비보호)
- `https://agentgateway.anyflow.net/ui/` -> `agentgateway` admin UI (로그인 필요)
- `https://api.anyflow.net/auth` -> `Authelia` 로그인 포털
- `https://api.anyflow.net/logout` -> 공통 로그아웃 진입점

로그인 계정:
- ID: `anyflow`
- PW: `StaffOnly`

## 핵심 구성

### kagent

- values: `apps/kagent/values.yaml`
- OpenAI provider는 `kagent-openai` Secret 참조를 사용한다.
- 실제 Grafana MCP secret: `apps/kagent/secret.grafana-mcp.yaml`
  - `kagent-grafana-mcp-ext` Secret를 선언한다.
  - `.gitignore`로 비추적한다.
- 예시 Grafana MCP secret: `apps/kagent/secret.grafana-mcp.example.yaml`
- `kagent`, generated agent, `querydoc`는 OTLP trace를 `otel-otlp-collector.observability.svc.cluster.local:4317`로 보낸다. tracing backend는 `Tempo`다.
- `kagent-controller` 외에 `agentgateway` 연동용 Service를 별도로 둔다.
  - `kagent-a2a` -> `appProtocol: kgateway.dev/a2a`
  - `kagent-mcp` -> `appProtocol: agentgateway.dev/mcp`
- `ReferenceGrant`: `apps/kagent/referencegrant-agentgateway.yaml`
- external route: `apps/kagent/httproute.yaml`
  - `/api/a2a`, `/mcp`는 `agentgateway-proxy`
  - `/`는 `kagent-ui`
  - `/logout`는 `api.anyflow.net/auth/logout`로 redirect
- auth policy: `apps/kagent/authzpolicy.yaml`
  - `kagent UI`만 보호
  - `/api/a2a`, `/mcp`, `/logout`는 예외 처리

### Observability

- `Jaeger`는 활성 구성에서 제거되었다.
- `apps/otel/otlp.yaml`의 collector는 trace를 `Tempo`로 export한다.
- `apps/grafana/values.yaml`의 datasource는 현재 `Prometheus`, `Tempo`를 사용한다.

### kmcp

- `kmcp-controller-manager`는 `kagent` namespace에 배치된다.
- 설치는 `Makefile`의 `kmcp-c`, 제거는 `kmcp-d`가 담당한다.
- `MCPServer`를 생성하면 deployment/service가 실제로 만들어지는 상태까지 검증했다.

### agentgateway

- values: `apps/agentgateway/values.yaml`
- 내부 proxy gateway: `apps/agentgateway/proxy-gateway.yaml`
- kagent upstream route: `apps/agentgateway/route-to-kagent.yaml`
- admin UI route: `apps/agentgateway/httproute.yaml`
  - `/` -> `/ui/` redirect
  - `/ui`, `/config_dump` -> `agentgateway-admin`
  - `/logout` -> `api.anyflow.net/auth/logout` redirect
- admin service: `apps/agentgateway/admin-service.yaml`
- auth policy: `apps/agentgateway/authzpolicy.yaml`
  - `agentgateway UI`만 보호
  - `/auth`, `/logout`는 예외 처리

### Authelia

- deployment/service: `apps/authelia/deployment.yaml`
- auth route: `apps/authelia/auth-httproute.yaml`
- logout route: `apps/authelia/logout-httproute.yaml`
- 실제 secret: `apps/authelia/secret.yaml`
  - `stringData` 기반 선언형 Secret
  - `.gitignore`로 비추적
- 예시 secret: `apps/authelia/secret.example.yaml`
- `create-secret.sh`는 제거되었다.

## agentgateway admin UI 노출 방식

`agentgateway` admin UI는 기본적으로 proxy pod 내부 loopback `127.0.0.1:15000`에 뜬다. `Service`만으로 직접 노출되지 않아서, 현재는 `agentgateway-proxy` deployment에 sidecar를 patch해 `0.0.0.0:15001 -> 127.0.0.1:15000` 포워딩을 만든다.

- admin service: `apps/agentgateway/admin-service.yaml`

즉 admin UI 기능 자체는 upstream이 제공하지만, 외부 공개 경로는 현재 patch 기반 구현이다.

## 재설치 / 복구 명령

### 전체 공개 상태 재구성

```sh
make authelia-c
make agentgateway-c
```

현재 remote 작업트리 기준으로 아래를 순서대로 다시 만든다.

- cert-manager issuer
- Authelia secret + deployment + auth/logout route
- kagent + Secret + A2A/MCP services + external route + certificate + auth policy
- kmcp CRD + controller
- agentgateway + proxy gateway + upstream route + admin patch + admin service + external route + certificate + auth policy

### 개별 명령

```sh
make kagent-c
make kmcp-c
make agentgateway-c
make authelia-c
```

## 현재 확인된 상태

- `kagent.anyflow.net` TLS: Ready
- `agentgateway.anyflow.net` TLS: Ready
- `kagent` UI: 로그인 후 접근 가능
- `agentgateway` UI: 로그인 후 접근 가능
- `kagent` A2A: 비보호 접근 유지
- `Authelia` 기반 SSO: 동작 확인
- `api.anyflow.net/logout`: 공통 로그아웃 진입점으로 동작 확인
- `MCPServer` 테스트 배포/생성: 동작 확인 후 테스트 리소스 삭제

## 남은 리스크

- `agentgateway` admin UI 노출은 controller가 관리하는 `agentgateway-proxy` deployment에 patch를 재적용하는 구조라, 재조정 시 patch가 사라질 수 있다. 현재는 `agentgateway-c`로 복구한다.
- `apps/authelia/secret.yaml`는 의도적으로 비추적 파일이다. 재설치 시 이 파일이 없으면 `authelia-c`는 실패한다.
