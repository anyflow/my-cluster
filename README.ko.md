# My Cluster (DRAFT)
단일 host에서 Kubernetes와 여기서 운용할 여러 app을 **'빠르게'** 설치/삭제하기 위한 프로젝트로서, 이들에 대한 사용법 확보 및 테스트가 주된 목적이다.

## 목표
- **'단일 명령'으로 Kubernetes 자체를 포함한 app을 설치/삭제 가능하도록**
    - 언제든 초기 설정에서 다시 시작할 수 있도록 하여, 설치/삭제 자체가 Kubernetes 및 app 파악에 장애물이 안되도록 하기 위함이다.
- **단일 host에서 실제 운용 가능하도록**
    - 사실 상 home server/cluster로 운용하기 위함이다. 당연하게도 internet 노출을 포함한다.

## 테스트 결과
- MacBook Pro 2011년 산(w/ 16G Memory), Ubuntu Linux 상에서 운용 중(Refer [My Cluster & its assets](https://www.anyflow.net) 섹션 참조).

## 사전 필요 사항
- **`docker`**: Kubernetes 기반이므로 container runtime이 당연스럽게 필요하다. `podman` 역시 아래의 `kind`가 지원하므로 가능할 듯 한데 테스트되지는 않았다.
- **`kind`**: Container 기반으로 단일 host에서의 Kubernetes를 지원하는 runtime. [kind 공식 가이드](https://kind.sigs.k8s.io/docs/user/quick-start/)에 OS별 설치 가이드가 잘 나와 있다.
- **`kubectl`**: Kubernetes 기본 명령 모듈. 이 역시 [Kuberenetes 공식 가이드](https://kubernetes.io/docs/tasks/tools/)의 `kubectl` 항목에 OS별 설치 가이드가 잘 나와 있다.
- **wildcard 인증서**: MyCluster의 기본 Gateway인 `waypoint`가 TLS 기반의 app 노출을 위해 사용한다. app 별 도메인 연결법은 [1. `.env` 설정](#1-env-설정) 섹션에서 설명한다. pem 형식으로 아래와 같이 위치시킨다.
  - **fullchain 인증서**: `/cert/fullchain.pem`
  - **개인키**: `/cert/privkey.pem`

## 사용법
모든 명령은 `Makefile` rule을 사용한다. 또한 대부분의 명령은 Kubernetes 자체를 포함한 app의 생성, 삭제로서, rule 명명 규칙은 생성(create)의 경우 `{name}-c`, 삭제(delete)는 `{name}-d`이다. 다음은 Kubernetes cluster와 Prometheus의 예이다.

```sh
# Kubernetes cluster
make cluster-c    # creation
make cluster-d    # deletion

# Prometheus
make prometheus-c # creation
make prometheus-d # deletion
```

이외에 각 app별 특화 사항에 대해서는 [`/apps`](./apps) 내 각 app directory의 `README.md`를 참고한다.

## Getting started

### 1. `.env` 설정
root에 `.env` 파일을 생성하여 아래와 같이 app별 도메인 값을 입력한다. 아래의 `...anyflow.net`은 예제로 실제 사용할 도메인명을 입력해야 한다([`sample.env`](sample.env) 참조).

```sh
DOMAIN_ARGOCD=argocd.anyflow.net
DOMAIN_DOCKER_REGISTRY=docker-registry.anyflow.net
...
```

### 2. Cluster 생성 및 주요 cluster level app, configuration 설치
Kubernetes 및 주요 cluster level의 설치/설정으로 구체적 내용 및 절차는 다음과 같다. 이외 각 app에 대해서는 위 사용법을 참조하여 별도로 필요에 따라 설치한다.

```bash
# 1. Clone the project
git clone https://github.com/anyflow/my-cluster.git

# 2. Change current working directory
cd my-cluster

# 3. Create Kubernetes cluster, configurate cluster level app, settings.
make initialize
```

참고로 아래는 `initialize` rule 내부에서 호출하는 rule 절차이다.

1. **`cluster-c`**: Kubernetes cluster 생성
2. **`metallb-c`**: Load Balancer 설치(metallb. Kubernetes API가 사용)
3. **`helm_repo-c`**: app용 helm repository 설치
4. **`istio-c`**: istio 설치
5. **`config-c`**: cluster level configuration 설정 e.g. namspace, metallb, gateway (, ingress)


## 파일/디렉토리 설명
```sh
root
├── cluster           # Kubernetes manifests in cluster level
├── apps              # app collection
│  ├── prometheus     # files for app - prometheus
│  ├── ...
├── cert              # cert. files
│  ├── fullchain.pem  # full chain certificate file (ignored in git)
│  ├── privkey.pem    # private key file (ignored in git)
│  ├── ...
├── nodes             # Kubernetes worker node files (ignored in git)
│  ├── worker0        # worker node 0
│  ├── ...
├── .env              # Environment Variables used in the Makefile (git ignored)
├── kind-config.yaml  # kind config
├── Makefile          # Makefile rules
├── README.md         # this file
├── .gitignore        # git ignore file
└── sample.env        # .env sample file
```

## 설계 상 결정 사항

### `kind` 사용
Minikube가 아닌 [`kind`](https://kind.sigs.k8s.io/)를 사용하는데, 처음 본 프로젝트 생성 당시 Minikube가 multi node를 지원하지 않았을 뿐 아니라 Kubernetes node를 container로 emulating하기에 **가볍고**, Kuberenetes 자체 개발을 위해 사용되었기 때문이다. 참고로, local 환경에서 Kuberenetes를 운용하기 위한 [Kuberenetes 공식 문서](https://kubernetes.io/docs/tasks/tools/) 상 첫 번째 옵션은 Minikube가 아닌 `kind`이다.

### `cluster`, `istio-system` 의 두 개 namespace 만 사용
이외의 namespace를 사용하지 않는 별다른 이유없이 편의성 때문이다. `istio-system`는 `istio` 및 eco family 설치 시 이외의 namespace를 사용할 경우 많은 시행 착오가 요구되기에 별도로 빠졌다.

### (`ingress` 대신) `Kubernetes Gateway API` 사용
`Kuberenetes Gateway API`는 `ingress`를 대체하는 새로운 Kubernetes API로서, Kubernetes Service를 외부에 노출하기 위해 default로 사용한다. 본 프로젝트는 `ingress`에 대한 설정도 일부 포함하지만 주석화를 통해 꺼져있다. [Kubernetes Gateway API로 Ingress 교체하기](https://www.anyflow.net/sw-engineer/replace-ingress-into-gatewayapi)는 이에 대한 자세한 설명이다.

### 3개의 worker node
local에서 동작함을 고려했을 때 Worker node를 3개나 운용하는 것은 불필요하나 Elasticsearch, MongoDB 등의 sharding, replication 테스트를 위해 3개로 설정했다. 불필요하다 생각되면 `kind-config.yaml`에서 1개로 설정해도 무방하다.

## 지원 app 목록
아래는 지원(✅) 또는 지원 예정(🚧)인 app 목록으로 세부 사항은 해당 app directory의 `README.md`를 참조한다.

- **✅ `docker-registry`**: [`/apps/docker-registry/README.ko.md`](./apps/docker-registry/README.md)
- **✅ `kagent` / `kmcp`**: `kagent` namespace에 Kubernetes-native agent와 MCP server controller가 설치되어 있다.
- **✅ `authelia`**: `kagent`, `agentgateway` UI를 위한 외부 인증 포털이다.
- **✅ `grafana` / `tempo` / `prometheus`**: 현재 observability stack이다. `kagent` tracing은 OTLP -> Tempo 경로를 사용한다.
- 🚧 `argocd`

## 기타 MyCluster에서 사용된 기법에 관한 설명

- **[기존 storage 재사용 in `kind` (w/ 데이터 유지)](./cluster/reuse-storage.kr.md)**: app, cluster가 재시작되어도 기존에 저장한 데이터를 그대로 사용하는 방법이다.
- **[Kubernetes Gateway API로 Ingress 교체하기](https://www.anyflow.net/sw-engineer/replace-ingress-into-gatewayapi)**: 제목 그대로 ingress를 Kubernetes Gateway API로 교체하는 방법이다.