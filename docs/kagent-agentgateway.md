# kagent + agentgateway 운영 메모

이 문서는 `~/workspace/my-cluster` remote 작업트리에 반영된 `kagent`/`agentgateway` 구성의 현재 상태를 압축해서 설명한다.

## 현재 상태

- `kagent`는 `default` 프로필로 설치되어 있다.
- `agentgateway`는 `kagent`의 A2A/MCP 앞단 프록시로 설치되어 있다.
- 외부 공개 호스트:
  - `https://kagent.anyflow.net/` -> `kagent` UI
  - `https://kagent.anyflow.net/api/a2a/...` -> `kagent` A2A
  - `https://kagent.anyflow.net/mcp` -> `kagent` MCP via `agentgateway`
  - `https://agentgateway.anyflow.net/ui/` -> `agentgateway` admin UI
- TLS 인증서는 `cert-manager` + `letsencrypt-production-http01` 기준으로 발급한다.

## 핵심 구성

### kagent

- values: `apps/kagent/values.yaml`
- OpenAI provider는 `kagent-openai` Secret 참조를 사용한다.
- `.env`의 `OPENAI_API_KEY`를 `Makefile`의 `kagent-secret-c`가 읽어 Secret을 만든다.
- `kagent-controller` 서비스 외에 agentgateway 연동용 Service를 별도로 둔다.
  - `kagent-a2a` -> `appProtocol: kgateway.dev/a2a`
  - `kagent-mcp` -> `appProtocol: agentgateway.dev/mcp`
- cross-namespace backend ref 허용용 `ReferenceGrant`를 `apps/kagent/referencegrant-agentgateway.yaml`에 둔다.

### agentgateway

- values: `apps/agentgateway/values.yaml`
- 내부 proxy gateway: `apps/agentgateway/proxy-gateway.yaml`
- kagent upstream route: `apps/agentgateway/route-to-kagent.yaml`
- public route:
  - `apps/agentgateway/public-httproute.yaml`
  - `/api/a2a`, `/mcp`는 `agentgateway-proxy`
  - `/`는 `kagent-ui`
- admin UI public route:
  - `apps/agentgateway/admin-httproute.yaml`
  - `/` -> `/ui/` redirect
  - `/ui`, `/config_dump` -> `agentgateway-admin`

## agentgateway admin UI 노출 방식

`agentgateway` admin UI는 기본적으로 proxy pod 내부의 loopback `127.0.0.1:15000`에 떠 있다. `Service`만으로는 직접 노출되지 않아서, 현재는 `agentgateway-proxy` deployment에 sidecar를 patch해서 `0.0.0.0:15001 -> 127.0.0.1:15000` 포워딩을 만든다.

- service: `apps/agentgateway/admin-service.yaml`
- patch target: `Makefile`의 `agentgateway-admin-patch-c`

즉 admin UI 기능 자체는 upstream이 제공하지만, 외부 공개 경로는 현재 patch 기반 구현이다.

## public gateway / certificate

- listeners: `cluster/public-gateway.yaml`
  - `kagent.anyflow.net`
  - `agentgateway.anyflow.net`
- certificates:
  - `certificate/kagent-anyflow-net.yaml`
  - `certificate/agentgateway-anyflow-net.yaml`

## 재설치 / 복구 명령

### 전체 공개 상태 재구성

```sh
make current-public-r
```

현재 remote 작업트리 기준으로 아래를 순서대로 다시 만든다.

- cert-manager issuer
- kagent + secret + A2A/MCP services
- agentgateway + proxy gateway + upstream route
- kagent public route + certificate
- agentgateway admin patch + admin service + admin route + certificate

### 개별 명령

```sh
make kagent-c
make agentgateway-c
make kagent-public-c
make agentgateway-public-c
make agentgateway-admin-patch-c
```

## 현재 확인된 상태

- `kagent.anyflow.net` TLS: Ready
- `agentgateway.anyflow.net` TLS: Ready
- `kagent` UI / A2A: 동작 확인
- `agentgateway` admin UI: 동작 확인

## 남은 리스크

- `agentgateway` admin UI 노출은 controller가 관리하는 `agentgateway-proxy` deployment에 patch를 재적용하는 구조라, 재조정 시 patch가 사라질 수 있다. 현재는 `agentgateway-admin-patch-c`와 `current-public-c`로 복구한다.
- 관측 시점에 `kagent-kmcp-controller-manager`는 `CrashLoopBackOff`였고, 이는 이번 public UI 노출 작업의 blocker는 아니었지만 후속 확인이 필요하다.
