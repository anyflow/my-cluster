# AGENTS.md

이 문서는 `~/workspace/my-cluster` 작업을 새 스레드/새 에이전트가 이어받을 때 필요한 현재 운영 기준을 요약한다.

## 운영 문서 기준

- 이 `AGENTS.md`가 현재 운영 상태를 압축한 단일 handoff 문서다.
- `kagent`, `kmcp`, `agentgateway`, `Authelia`, tracing/Tempo, 외부 공개 경로 관련 작업은 아래 `kagent / agentgateway 운영 기준` 섹션을 먼저 확인할 것.

## 개요

- 이 저장소는 `kind` 기반의 로컬 Kubernetes 클러스터 `my-cluster`를 운영한다.
- 기본 컨텍스트는 `kind-my-cluster`다.
- 현재 ingress 노출 방식은 `MetalLB VIP`가 아니라 `NodePort + host iptables DNAT`다.

## 현재 ingress 구조

- `public-gateway` 서비스는 `cluster` 네임스페이스에 있으며 현재 `NodePort` 타입이다.
- 고정 포트:
  - HTTP: `30080`
  - HTTPS: `30443`
  - Status: `30812`
- 고정 포트 선언 파일:
  - `cluster/values.ingressgateway.yaml`
- 호스트 포워딩:
  - host `80` -> `my-cluster-worker:<30080>`
  - host `443` -> `my-cluster-worker:<30443>`
- 실제 DNAT 목적지 IP는 worker 컨테이너 IP이므로 `Makefile`의 `port_forward`가 `docker inspect`로 동적으로 구한다.

## Makefile 운영 규칙

- `create-sidecar` / `create-ambient`는 다음 순서를 따른다.
  1. `init`
  2. `enlarge_open_file_count`
  3. `port_forward`
  4. `istio-*`
  5. `app`
- `enlarge_open_file_count`는 host 전역 튜닝이지만, 반복 실행해도 같은 값을 다시 쓰는 동작이라 `create-*` 흐름에 포함해도 무방하다.
- `cluster-d`는 `port_forward_clean`을 먼저 수행한 뒤 `kind delete cluster -n my-cluster`를 실행한다.
- `port_forward`는 `kubectl get svc`로 NodePort를 조회하지 않는다.
  - 고정 포트 `30080/30443`를 사용한다.
  - 클러스터 생성 직후 먼저 실행되어도 된다.
- ingress gateway 생성 시점부터 고정 포트를 쓰도록 `helm upgrade`는 반드시 `cluster/values.ingressgateway.yaml`를 사용해야 한다.
- 향후 ingress 포트를 바꾸면 다음을 함께 수정해야 한다.
  - `cluster/values.ingressgateway.yaml`
  - `Makefile`의 `INGRESS_HTTP_NODEPORT`, `INGRESS_HTTPS_NODEPORT`
  - 공유기 포트포워딩/외부 문서

## DNS / 호스트 전제

- `alpine` 호스트는 한때 DNS 문제로 이미지 pull이 실패했다.
- 현재 호스트 DNS는 다음 전제로 맞춰져 있다.
  - `/etc/resolv.conf` -> `nameserver 192.168.0.1`
  - `/etc/udhcpc/udhcpc.conf` -> `RESOLV_CONF="no"`
- 위 설정이 깨지면 `kind` 노드의 이미지 pull이 다시 실패할 수 있다.

## Alpine 호스트 환경

- 호스트명: `alpine.anyflow.net`
- 네트워크 인터페이스:
  - `eth0` -> `192.168.0.4/24`
  - `wlan0` -> `192.168.0.10/24`
- 기본 라우트:
  - `default via 192.168.0.1 dev eth0 metric 202`
  - `default via 192.168.0.1 dev wlan0 metric 303`
- kind bridge:
  - `br-20ea4daf2405` -> `172.18.0.0/16`
  - `my-cluster-worker` -> `172.18.0.2`
  - `my-cluster-control-plane` -> `172.18.0.3`
- 현재 host-level ingress DNAT는 `172.18.0.2`의 고정 NodePort로 보낸다.
  - `80 -> 172.18.0.2:30080`
  - `443 -> 172.18.0.2:30443`
- `wlan0`는 여전히 살아 있지만, 현재 운영 결론상 ingress fix의 핵심은 `VIP`가 아니라 `NodePort`로 직접 포워딩하는 방식이다.

## 호스트명 / SNI 주의

- ingress `Gateway`와 `VirtualService`는 `*.anyflow.net` / `api.anyflow.net` 기준으로 작성되어 있다.
- `anyflow.iptime.org`는 DDNS/호스트 도달용일 뿐, 애플리케이션 ingress host로는 맞지 않는다.
- HTTPS 테스트는 다음 기준으로 해야 한다.
  - `api.anyflow.net`
- `anyflow.iptime.org`로 HTTPS를 직접 테스트하면 host/SNI mismatch로 잘못된 결론이 나올 수 있다.

## 공유기 / 외부 진입 환경

- 아래 정보는 공유기 UI를 직접 읽은 것이 아니라, 현재 관측된 동작을 기준으로 정리한 운영 사실이다.
- DDNS:
  - `anyflow.iptime.org`
  - 2026-03-29 기준 공인 IP는 `222.108.188.34`
- SSH:
  - 외부 접근 경로는 `anyflow.iptime.org:30022 -> alpine:22`
  - 작업자의 로컬 `~/.ssh/config`에는 `alpine`에 대해 LAN 우선 fallback이 있다.
    - LAN 가능 시 `192.168.0.4:22`
    - 아니면 `anyflow.iptime.org:30022`
- HTTPS ingress:
  - 공유기 `443`은 `alpine` 호스트 `443`으로 들어오고, 호스트 iptables가 이를 `my-cluster-worker:30443`으로 DNAT한다.
  - 성공 조건은 단순히 `443` 오픈이 아니라 `Host/SNI=api.anyflow.net`이다.
  - 검증 예:
    - `curl -kI --resolve api.anyflow.net:443:222.108.188.34 https://api.anyflow.net/`
    - 기대 응답: `HTTP/2 301`

## 이미지 운영 상태

- `docserver` 배포 이미지는 현재 GHCR을 사용한다.
  - `ghcr.io/anyflow/docserver:latest`
- `dockebi` 배포 이미지들도 현재 GHCR을 사용한다.
  - `ghcr.io/anyflow/dockebi:latest`
- 관련 배포 파일:
  - `apps/docserver/deployment/deployment.yaml`
  - `apps/dockebi/deployment/deployment.yaml`

## 앱 운영 상태

### market-reporter

- 앱 경로: `apps/market-reporter` (nested git repository)
- 이 앱/디렉터리를 수정할 때는 루트 `AGENTS.md`를 읽은 뒤 `apps/market-reporter/AGENTS.md`도 반드시 읽을 것.
- 현재 `kagent` 네임스페이스에서 공통 `stock-mcp`가 `apps/kagent/custom/stock-mcp.yaml` 선언형 `MCPServer` 기반 `Deployment/Service`로 떠 있다.
- target별 agent는 `apps/kagent/custom` 선언형 YAML로 수동 관리한다.
  - `tesla-stock-agent`
  - `samsung-stock-agent`
- `stock-agent`는 `apps/kagent/custom/stock-agent.yaml` 선언형 CRD로 별도 관리된다.
- target별 daily CronJob도 `apps/kagent/custom` 선언형 YAML로 수동 관리한다.
  - `tesla-stock-daily-report` (`0 8 * * *`, `Asia/Seoul`)
  - `samsung-stock-daily-report` (`5 8 * * *`, `Asia/Seoul`)
- 이름 변경 이후 새 CronJob은 아직 scheduled 실행 전이며, 기존 reports 산출물은 A2A/MCP 조회로 확인했다.
- 루트 `Makefile` 기준 진입점은 `stock-mcp-c`, `stock-mcp-d`, `stock-mcp-r`다.

### anyflow-blog

- 앱 경로: `apps/anyflow-blog` (nested git repository)
- 이 앱/디렉터리를 수정할 때는 루트 `AGENTS.md`를 읽은 뒤 `apps/anyflow-blog/AGENTS.md`도 반드시 읽을 것.
- 현재 `service` 네임스페이스에 `anyflow-blog` `Deployment/Service`가 올라와 있다.
- 외부 노출은 `apps/anyflow-blog/deployment/httproute.yaml` 기준이며 host는 `blog.anyflow.net`이다.
- `cluster` 네임스페이스의 `blog-anyflow-net` certificate는 현재 `Ready=True`다.
- 루트 `Makefile` 기준 진입점은 `anyflow-blog-c`, `anyflow-blog-d`, `anyflow-blog-r`다.

## kagent / agentgateway 운영 기준

이 섹션은 기존 별도 kagent/agentgateway 운영 메모를 흡수한 현재 운영 기준이다.

### 현재 상태

- `kagent`는 `0.9.0`, `agentgateway`는 `1.1.0`, `kmcp`는 `0.2.8` 기준으로 설치되어 있다.
- `kagent`는 `default` 프로필 기반이지만 현재 클러스터에서는 `argo-rollouts`, `cilium`, `kgateway` agent를 비활성화한다.
- `kmcp`는 현재 standalone chart가 아니라 `kagent` chart에 bundled 된 형태로 `kagent` namespace에 배치된다.
- `agentgateway`는 `kagent`의 A2A/MCP 앞단 프록시로 설치되어 있다.
- `kagent` namespace는 ambient + 전용 waypoint(`waypoint-kagent`)가 적용되어 있다.
- `Authelia`는 `api.anyflow.net/auth` 경로로 PoC IdP와 실제 credential 검증 화면을 제공한다.
- `oauth2-proxy`는 `public-gateway`의 단일 ext_authz provider로 UI session cookie와 API/A2A/MCP Bearer JWT를 검증한다.
- kagent/agentgateway UI의 브라우저 인증은 oauth2-proxy가 세션을 관리하고 Authelia IdP authorization endpoint로 직접 redirect한다.

### 외부 엔드포인트

- `https://kagent.anyflow.net/` -> `kagent` UI (로그인 필요)
- `https://kagent.anyflow.net/api/a2a/...` -> `kagent` A2A (Bearer JWT 필요)
- `https://kagent.anyflow.net/mcp` -> `kagent` MCP via `agentgateway` (Bearer JWT 필요)
- `https://agentgateway.anyflow.net/ui/` -> `agentgateway` admin UI (로그인 필요)
- `https://kagent.anyflow.net/oauth2/...`, `https://agentgateway.anyflow.net/oauth2/...` -> `oauth2-proxy` OIDC redirect/callback
- `https://api.anyflow.net/oauth2/...` -> 공통 logout chain용 `oauth2-proxy`
- `https://api.anyflow.net/auth` -> `Authelia` IdP 로그인 포털
- `https://api.anyflow.net/logout` -> 공통 로그아웃 진입점. oauth2-proxy session cookie를 먼저 제거한 뒤 Authelia logout으로 이동한다.

### 핵심 구성

##### kagent

- values: `apps/kagent/values.yaml`
- `providers.openAI`는 kagent SDK 초기화를 위한 dummy Secret `apps/kagent/secret.dummy.yaml`를 참조한다.
- 실제 OpenAI credential은 agentgateway의 `apps/agentgateway/secret.openai.yaml`와 `AgentgatewayBackend/openai`에서만 관리한다.
- 실제 Grafana MCP secret: `apps/kagent/secret.grafana-mcp.yaml`
  - `kagent-grafana-mcp-ext` Secret를 선언한다.
  - `.gitignore`로 비추적한다.
- 예시 Grafana MCP secret: `apps/kagent/secret.grafana-mcp.example.yaml`
- `kagent`, generated agent, `querydoc`는 OTLP trace를 `otel-otlp-collector.observability.svc.cluster.local:4317`로 보낸다. tracing backend는 `Tempo`다.
- `proxy.url`은 현재 `agentgateway-proxy.agentgateway-system.svc.cluster.local`을 사용한다.
- `kagent-tools`는 chart 기본 upstream image를 사용한다.
- `kagent-controller` 외에 `agentgateway` 연동용 Service를 별도로 둔다.
  - `kagent-a2a` -> `appProtocol: kgateway.dev/a2a`
  - `kagent-mcp` -> `appProtocol: agentgateway.dev/mcp`
- `ReferenceGrant`: `apps/kagent/referencegrant-agentgateway.yaml`
- external route: `apps/kagent/httproute.yaml`
  - `/oauth2`는 `oauth2-proxy`
  - `/api/a2a`, `/mcp`는 `agentgateway-proxy`
  - `/api`는 `kagent-controller`
  - `/`는 `kagent-ui`
  - `/logout`는 `https://api.anyflow.net/oauth2/sign_out?rd=https%3A%2F%2Fapi.anyflow.net%2Fauth%2Flogout`로 redirect
- auth policy: `apps/kagent/authzpolicy.yaml`
  - `kagent UI`, `/api`, `/api/a2a`, `/mcp`를 `oauth2-proxy`로 보호
  - `/oauth2`, `/logout`만 예외 처리
- Helm 기본 prebuilt `istio-agent`를 사용한다.
- `stock-agent`도 커스텀 선언형 CRD `apps/kagent/custom/stock-agent.yaml`로 관리한다.
- `stock-mcp`, target별 stock agent, daily report CronJob은 `apps/kagent/custom` 선언형 YAML로 수동 관리한다.

##### Observability

- `Jaeger`는 활성 구성에서 제거되었다.
- `apps/otel/otlp.yaml`의 collector는 trace를 `Tempo`로 export한다.
- `apps/grafana/values.yaml`의 datasource는 현재 `Prometheus`, `Tempo`를 사용한다.
- `kagent-grafana-mcp`는 현재 `GRAFANA_URL=http://grafana.observability.svc.cluster.local`을 사용한다.
- `grafana-mcp` 컨테이너 이미지는 upstream이 semver tag를 제공하지 않아 `latest` 공개 digest를 `Makefile`에서 patch로 pin 한다.

##### kmcp

- `kagent-kmcp-controller-manager`는 `kagent` namespace에 배치된다.
- 루트 `Makefile`의 `kmcp-c` / `kmcp-d`는 standalone kmcp chart 설치가 아니라 bundled controller readiness 확인 및 legacy release 정리 역할만 한다.

##### agentgateway

- values: `apps/agentgateway/values.yaml`
- 내부 proxy gateway: `apps/agentgateway/gateway.proxy.yaml`
- kagent upstream route: `apps/agentgateway/httproute.kagent.yaml`
- OpenAI backend route: `apps/agentgateway/agentgatewaybackend.openai.yaml`
- admin UI route: `apps/agentgateway/httproute.agentgateway-admin.yaml`
  - `/` -> `/ui/` redirect
  - `/oauth2` -> `oauth2-proxy`
  - `/ui`, `/config_dump` -> `agentgateway-admin`
  - `/logout` -> `https://api.anyflow.net/oauth2/sign_out?rd=https%3A%2F%2Fapi.anyflow.net%2Fauth%2Flogout` redirect
- admin service: `apps/agentgateway/service.agentgateway-admin.yaml`
- auth policy: `apps/agentgateway/authorizationpolicy.agentgateway-admin.yaml`
  - `agentgateway UI`를 `oauth2-proxy`로 보호
  - `/oauth2`, `/logout`만 예외 처리
- `httproute.kagent.yaml`은 현재 다음 내부 backend를 header-match로 직접 라우팅한다.
  - `stock-mcp.kagent`
  - `kagent-tools.kagent`
  - `kagent-grafana-mcp.kagent`
  - `samsung-stock-agent.kagent` -> `samsung-stock-agent-a2a` -> `samsung-stock-agent:8080`
  - `tesla-stock-agent.kagent` -> `tesla-stock-agent-a2a` -> `tesla-stock-agent:8080`
  - fallback: `kagent-mcp`, `kagent-a2a`
- `stock-agent`의 하위 agent A2A 호출은 `agentgateway`를 경유하지만 `kagent-controller`로 URLRewrite하지 않고 각 agent runtime Service로 직접 라우팅한다.

##### Authelia

- deployment/service: `apps/authelia/deployment.yaml`
- auth route: `apps/authelia/auth-httproute.yaml`
  - `/auth` -> `authelia`
  - `/oauth2` -> `oauth2-proxy`
- logout route: `apps/authelia/logout-httproute.yaml`
- 실제 secret: `apps/authelia/secret.yaml`
  - `stringData` 기반 선언형 Secret
  - `.gitignore`로 비추적
- 예시 secret: `apps/authelia/secret.example.yaml`
- `create-secret.sh`는 제거되었다.
- OIDC provider/client 설정을 포함한다.
  - `my-cluster-oauth2-proxy`: browser auth code flow용
    - `consent_mode: implicit`으로 Authelia consent 화면을 건너뛰고 oauth2-proxy callback을 처리한다.
  - `my-cluster-local`: local Mac client_credentials Bearer JWT 검증용

##### oauth2-proxy

- Helm values: `apps/oauth2-proxy/values.yaml`
- 실제 secret: `apps/oauth2-proxy/secret.yaml`
  - `.gitignore`로 비추적한다.
- 예시 secret: `apps/oauth2-proxy/secret.example.yaml`
- `ReferenceGrant`: `apps/oauth2-proxy/referencegrant-agentgateway.yaml`
- Makefile 진입점: `oauth2-proxy-c`, `oauth2-proxy-d`
- Helm chart: `oauth2-proxy/oauth2-proxy` `10.4.3`
- image: `quay.io/oauth2-proxy/oauth2-proxy:v7.15.2`
- `configFile`은 chart default와 같은 설정을 원칙적으로 생략하고, 운영 contract상 명시가 필요한 설정만 남긴다.
- cookie domain은 `.anyflow.net`이다.
- `api_routes`는 `^/api/.*`, `^/mcp.*`이며 무토큰 요청은 login redirect가 아니라 401/403으로 거부한다.
- `skip_provider_button = true`로 Authelia IdP authorization endpoint로 직접 보낸다.
- `/logout`은 `https://api.anyflow.net/oauth2/sign_out`을 먼저 거쳐 session cookie를 지우고, `rd`로 Authelia logout을 호출해 IdP session도 지운다.
- Bearer JWT는 Authelia issuer `https://api.anyflow.net/auth`와 audience `my-cluster-api` 기준으로 검증한다.
- local Mac credential은 repository가 아니라 `~/.ai/secrets/my-cluster/oauth-client.env`에 둔다.

### agentgateway admin UI 노출 방식

`agentgateway` admin UI는 기본적으로 proxy pod 내부 loopback `127.0.0.1:15000`에 뜬다. `Service`만으로 직접 노출되지 않아서, 현재는 `agentgateway-proxy` deployment에 sidecar를 patch해 `0.0.0.0:15001 -> 127.0.0.1:15000` 포워딩을 만든다.

- admin service: `apps/agentgateway/service.agentgateway-admin.yaml`

즉 admin UI 기능 자체는 upstream이 제공하지만, 외부 공개 경로는 현재 patch 기반 구현이다.

### 재설치 / 복구 명령

##### 전체 공개 상태 재구성

```sh
make authelia-c
make oauth2-proxy-c
make agentgateway-c
```

현재 remote 작업트리 기준으로 아래를 순서대로 다시 만든다.

- cert-manager issuer
- Authelia secret + deployment + auth/logout route
- oauth2-proxy secret + Helm release + ReferenceGrant
- kagent + bundled kmcp + Secret + A2A/MCP services + external route + certificate + auth policy
- agentgateway + proxy gateway + upstream route + admin patch + admin service + external route + certificate + auth policy
- `stock-mcp` common MCP + tesla/samsung stock agents + cronjobs 복원
- stock-agent 복원

##### 개별 명령

```sh
make kagent-c
make kmcp-c
make oauth2-proxy-c
make stock-mcp-c
make stock-agent-c
make agentgateway-c
make authelia-c
```

### 현재 확인된 상태

- `kagent.anyflow.net` TLS: Ready
- `agentgateway.anyflow.net` TLS: Ready
- `kagent` UI: 로그인 후 접근 가능
- `agentgateway` UI: 로그인 후 접근 가능
- `Authelia` OIDC discovery/JWKS/token endpoint: 동작 확인
- `oauth2-proxy` direct provider redirect: 동작 확인
- `kagent` controller API(`/api/agents`): Bearer JWT 요청 시 public-gateway에서 `kagent-controller`로 라우팅되어 정상 응답 확인
- `kagent` A2A/MCP 무토큰 요청: 401/403으로 차단
- `kagent` A2A/MCP Bearer JWT 요청: oauth2-proxy 검증 후 backend 도달 확인
- `api.anyflow.net/logout`: oauth2-proxy + Authelia session logout chain으로 동작 확인
- `stock-agent`, `tesla-stock-agent`, `samsung-stock-agent`: `Ready=True`, `Accepted=True`
- `stock-mcp`: `MCPServer Ready=True`; target별 Agent가 `kind: MCPServer`로 직접 참조
- `kagent-grafana-mcp`, `kagent-tool-server`: `RemoteMCPServer Accepted=True`
- `observability-agent`: Grafana datasource 조회 정상 (`Prometheus`, `Tempo`)
- `stock-agent` A2A 질의: samsung/tesla subagent 취합 응답 확인

### TODO

- `agentgateway` admin UI 노출은 현재 `agentgateway-proxy` deployment에 `admin-ui-proxy` sidecar patch를 재적용하는 구조다. patch 없는 방식으로 전환하거나, 현재 구조를 유지한다면 `agentgateway-c` 복구 절차를 계속 보장할 것.
- `apps/authelia/secret.yaml`는 의도적으로 비추적 파일이다. 재설치 시 필수라는 점을 유지 문서/운영 절차에 계속 반영할 것.
- `apps/oauth2-proxy/secret.yaml`와 `~/.ai/secrets/my-cluster/oauth-client.env`도 의도적으로 비추적이다.
- `kagent-grafana-mcp` upstream은 현재 semver image tag를 제공하지 않는다. `Makefile`의 digest pin을 주기적으로 갱신할 절차를 둘 것.
- `kagent-tools`의 Istio waypoint tool은 chart 기본 upstream 동작을 따른다. waypoint list/status 인자 문제가 재현되면 upstream 수정 여부를 먼저 확인할 것.
- 커스텀 선언형으로 관리하는 `stock-agent`, `tesla-stock-agent`, `samsung-stock-agent`, target별 CronJob은 재설치 후 동작을 계속 검증할 것.

## 제거된 항목

- `MetalLB`는 현재 클러스터/Makefile 기준 제거되었다.
- `cluster/metallb-config.yaml`는 삭제되었다.
- `dockebi-get-stuff` CronJob은 런타임과 배포 구성에서 제거되었다.
  - `apps/dockebi/deployment/kustomization.yaml`에서 제외됨
  - `apps/dockebi/deployment/cronjob.yaml`는 삭제됨

## 작업 기준

- runtime 상의 application 변경 요청은 별도 요구가 없는한 GitOps 기반으로 대응할 것. 즉, 코드 상에 먼저 변경하고 이를 apply하도록.
- 이 저장소의 source of truth는 `alpine remote`의 `~/workspace/my-cluster` 작업트리다.
- harness 역시 로컬이 아니라 `alpine remote`의 `~/workspace/my-cluster/.ai` 기준으로 확인할 것.
- 리소스/manifest 변경, 검증, 커밋은 모두 remote 기준으로 수행할 것.
- 로컬 작업트리의 리소스 변경은 원칙적으로 의미 없는 임시 작업으로 취급할 것.
- 로컬 변경은 문서 초안 같은 예외적 경우에만 허용하고, 리소스 변경은 로컬에서 커밋하지 말 것.

## 작업 시 주의

- `MetalLB`를 다시 도입하지 말 것. 현재 ingress는 `NodePort + port_forward`가 기준이다.
- 공유기 포워딩이나 외부 테스트를 볼 때는 `anyflow.iptime.org`와 `api.anyflow.net`의 역할을 혼동하지 말 것.
  - `anyflow.iptime.org` = DDNS / 호스트 도달
  - `api.anyflow.net` = ingress host / TLS SNI
- ingress를 수정할 때는 `Gateway/VirtualService` host가 `*.anyflow.net` 체계와 일치하는지 먼저 확인할 것.
- host-level 80/443 노출 문제를 볼 때는 다음 순서로 확인할 것.
  1. `kubectl get svc -n cluster public-gateway`
  2. `make port_forward`
  3. `curl -I -H 'Host: api.anyflow.net' http://192.168.0.4/`
  4. `curl -kI --resolve api.anyflow.net:443:<host-ip> https://api.anyflow.net/`
- 호스트 재부팅 후에는 `make port_forward` 재실행이 필요할 수 있다. iptables 규칙은 영속적이지 않다.
