# kagent + agentgateway 운영 메모

이 문서는 `~/workspace/my-cluster` remote 작업트리에 반영된 `kagent`, `kmcp`, `agentgateway`, `Authelia` 구성을 압축해서 설명한다.

## 현재 상태

- `kagent`는 `0.9.0`, `agentgateway`는 `1.1.0`, `kmcp`는 `0.2.8` 기준으로 설치되어 있다.
- `kagent`는 `default` 프로필 기반이지만 현재 클러스터에서는 `argo-rollouts`, `cilium`, `kgateway` agent를 비활성화한다.
- `kmcp`는 현재 standalone chart가 아니라 `kagent` chart에 bundled 된 형태로 `kagent` namespace에 배치된다.
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

## 핵심 구성

### kagent

- values: `apps/kagent/values.yaml`
- OpenAI provider는 `kagent-openai` Secret 참조를 사용한다.
- 실제 Grafana MCP secret: `apps/kagent/secret.grafana-mcp.yaml`
  - `kagent-grafana-mcp-ext` Secret를 선언한다.
  - `.gitignore`로 비추적한다.
- 예시 Grafana MCP secret: `apps/kagent/secret.grafana-mcp.example.yaml`
- `kagent`, generated agent, `querydoc`는 OTLP trace를 `otel-otlp-collector.observability.svc.cluster.local:4317`로 보낸다. tracing backend는 `Tempo`다.
- `proxy.url`은 현재 `agentgateway-proxy.agentgateway-system.svc.cluster.local`을 사용한다.
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
- Helm 기본 prebuilt 중 `istio-agent`는 비활성화하고, 커스텀 선언형 CRD `apps/kagent/custom/istio-agent.yaml`를 복원 적용한다.
- `stock-agent`도 커스텀 선언형 CRD `apps/kagent/custom/stock-agent.yaml`로 관리한다.

### Observability

- `Jaeger`는 활성 구성에서 제거되었다.
- `apps/otel/otlp.yaml`의 collector는 trace를 `Tempo`로 export한다.
- `apps/grafana/values.yaml`의 datasource는 현재 `Prometheus`, `Tempo`를 사용한다.
- `kagent-grafana-mcp`는 현재 `GRAFANA_URL=http://grafana.observability.svc.cluster.local`을 사용한다.
- `grafana-mcp` 컨테이너 이미지는 upstream이 semver tag를 제공하지 않아 `latest` 공개 digest를 `Makefile`에서 patch로 pin 한다.

### kmcp

- `kagent-kmcp-controller-manager`는 `kagent` namespace에 배치된다.
- 루트 `Makefile`의 `kmcp-c` / `kmcp-d`는 standalone kmcp chart 설치가 아니라 bundled controller readiness 확인 및 legacy release 정리 역할만 한다.

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
- `route-to-kagent.yaml`은 현재 다음 내부 backend를 header-match로 직접 라우팅한다.
  - `market-intelligence-mcp.kagent`
  - `kagent-tools.kagent`
  - `kagent-grafana-mcp.kagent`
  - `promql-agent.kagent`
  - `samsung-electronics-intelligence-analyst.kagent`
  - `tesla-intelligence-analyst.kagent`
  - fallback: `kagent-mcp`, `kagent-a2a`

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
- kagent + bundled kmcp + Secret + A2A/MCP services + external route + certificate + auth policy
- agentgateway + proxy gateway + upstream route + admin patch + admin service + external route + certificate + auth policy
- market-intelligence common MCP + tesla/samsung target agents + cronjobs 복원
- stock-agent 복원
- custom istio-agent 복원

### 개별 명령

```sh
make kagent-c
make kmcp-c
make market-intelligence-c
make stock-agent-c
make istio-agent-c
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
- `stock-agent`, `tesla-intelligence-analyst`, `samsung-electronics-intelligence-analyst`: `Ready=True`, `Accepted=True`
- `market-intelligence-mcp`: `MCPServer Ready=True`, `RemoteMCPServer Accepted=True`
- `kagent-grafana-mcp`, `kagent-tool-server`: `RemoteMCPServer Accepted=True`
- `observability-agent`: Grafana datasource 조회 정상 (`Prometheus`, `Tempo`)
- `stock-agent` A2A 질의: samsung/tesla subagent 취합 응답 확인

## TODO

- `agentgateway` admin UI 노출은 현재 `agentgateway-proxy` deployment에 `admin-ui-proxy` sidecar patch를 재적용하는 구조다. patch 없는 방식으로 전환하거나, 현재 구조를 유지한다면 `agentgateway-c` 복구 절차를 계속 보장할 것.
- `apps/authelia/secret.yaml`는 의도적으로 비추적 파일이다. 재설치 시 필수라는 점을 유지 문서/운영 절차에 계속 반영할 것.
- `kagent-grafana-mcp` upstream은 현재 semver image tag를 제공하지 않는다. `Makefile`의 digest pin을 주기적으로 갱신할 절차를 둘 것.
- `kagent-tools`의 `istio_list_waypoints`는 현재 `istioctl waypoint list`만 실행해 cluster-wide waypoint를 제대로 보여주지 못한다. upstream 구현 수정 또는 별도 우회 절차를 마련할 것.
- `kagent-tools`의 `istio_waypoint_status`는 현재 `waypoint-kagent -n kagent`에 대해서도 `istioctl waypoint status ...`가 `exit status 1`로 실패한다. 실제 실행 인자, `istioctl` 버전, 출력 파싱 경로를 upstream 기준으로 추적해 수정할 것.
- 커스텀 선언형으로 관리하는 `stock-agent`, `istio-agent`는 Helm 기본 prebuilt 정의와 drift가 나지 않도록 재설치 후 동작을 계속 검증할 것.
