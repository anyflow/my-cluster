include .env

export

INGRESS_HTTP_NODEPORT ?= 30080
INGRESS_HTTPS_NODEPORT ?= 30443
SSH_BLOCKLIST_IPS ?= \
	172.239.9.59 \
	103.105.176.70 \
	103.4.145.50 \
	36.50.177.119 \
	121.29.4.103 \
	14.103.118.153 \
	35.225.56.202 \
	211.213.96.171
SSH_ALLOWLIST_IPS ?= \
	192.168.0.0/24 \
	27.122.242.65/32 \
	117.111.8.13/32
GATEWAY_API_VERSION ?= v1.5.1
GATEWAY_API_STANDARD_INSTALL ?= https://github.com/kubernetes-sigs/gateway-api/releases/download/$(GATEWAY_API_VERSION)/standard-install.yaml
ISTIO_VERSION ?= 1.29.1
ISTIO_REVISION ?= $(ISTIO_VERSION)
ISTIO_DIST_DIR ?= istio-$(ISTIO_VERSION)
KIALI_CHART_VERSION ?= 2.23.0
PROMETHEUS_CHART_VERSION ?= 28.14.1
GRAFANA_CHART_VERSION ?= 10.5.15
OTEL_OPERATOR_CHART_VERSION ?= 0.109.0
TEMPO_CHART_VERSION ?= 1.24.4
AGENTGATEWAY_CHART_VERSION ?= 1.1.0
KAGENT_CHART_VERSION ?= 0.9.0
KMCP_CHART_VERSION ?= 0.2.8
KAGENT_GRAFANA_MCP_IMAGE ?= mcp/grafana@sha256:18622ba05381b08c622666c1cb1f92f05d54cb23709b7d580ab783e710973f37
AUTHELIA_VERSION ?= 4.39.16
OAUTH2_PROXY_CHART_VERSION ?= 10.4.3
PROMETHEUS_POD_MONITORS_CRD := https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.72.0/example/prometheus-operator-crd/monitoring.coreos.com_podmonitors.yaml
PROMETHEUS_SERVICE_MONITORS_CRD := https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.72.0/example/prometheus-operator-crd/monitoring.coreos.com_servicemonitors.yaml


create-sidecar: init
	$(MAKE) port_forward
	$(MAKE) metric-server-c
	$(MAKE) istio-sidecar
	$(MAKE) app

create-ambient: init
	$(MAKE) port_forward
	$(MAKE) metric-server-c
	$(MAKE) istio-ambient
	$(MAKE) app

init: cluster-c helm_repo-c
istio-sidecar: istio-sidecar-c config-c gateway-c cert_manager-c api-tls-c
istio-ambient: istio-ambient-c config-c gateway-c cert_manager-c api-tls-c
app: docserver-c dockebi-c


observability:  prometheus-c grafana-c otel-c otel-prometheus-c kiali-c
otel: otel-c otel-prometheus-c


cluster-c:
	kind create cluster --config ./kind-config.yaml
cluster-d:
	-$(MAKE) port_forward_clean
	kind delete cluster -n my-cluster

cilium-c:
	helm repo add cilium https://helm.cilium.io/
	docker pull quay.io/cilium/cilium:v1.17.1
	kind load docker-image quay.io/cilium/cilium:v1.17.1
	helm upgrade cilium cilium/cilium \
	--version 1.17.1 \
	--namespace kube-system \
	--set image.pullPolicy=IfNotPresent \
	--set envoy.enabled=false \
	--set hubble.enabled=false \
	--set clustermesh.enabled=false \
	--set operator.enabled=true

# DO it to prevent "failed to create fsnotify watcher: too many open files" error in "kubectl logs -f" command
enlarge_open_file_count:
	sudo sysctl -w fs.inotify.max_user_watches=2099999999
	sudo sysctl -w fs.inotify.max_user_instances=2099999999
	sudo sysctl -w fs.inotify.max_queued_events=2099999999

port_forward:
	@INGRESS_IP=$$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' my-cluster-worker); \
	sudo iptables -C DOCKER -d $$INGRESS_IP/32 -p tcp --dport $(INGRESS_HTTP_NODEPORT) -j ACCEPT 2>/dev/null || sudo iptables -I DOCKER 2 -d $$INGRESS_IP/32 -p tcp --dport $(INGRESS_HTTP_NODEPORT) -j ACCEPT; \
	sudo iptables -C DOCKER -d $$INGRESS_IP/32 -p tcp --dport $(INGRESS_HTTPS_NODEPORT) -j ACCEPT 2>/dev/null || sudo iptables -I DOCKER 3 -d $$INGRESS_IP/32 -p tcp --dport $(INGRESS_HTTPS_NODEPORT) -j ACCEPT; \
	sudo iptables -t nat -C DOCKER -p tcp --dport 80 -j DNAT --to-destination $$INGRESS_IP:$(INGRESS_HTTP_NODEPORT) 2>/dev/null || sudo iptables -t nat -I DOCKER 3 -p tcp --dport 80 -j DNAT --to-destination $$INGRESS_IP:$(INGRESS_HTTP_NODEPORT); \
	sudo iptables -t nat -C DOCKER -p tcp --dport 443 -j DNAT --to-destination $$INGRESS_IP:$(INGRESS_HTTPS_NODEPORT) 2>/dev/null || sudo iptables -t nat -I DOCKER 4 -p tcp --dport 443 -j DNAT --to-destination $$INGRESS_IP:$(INGRESS_HTTPS_NODEPORT); \
	echo "port_forward -> $$INGRESS_IP http=$(INGRESS_HTTP_NODEPORT) https=$(INGRESS_HTTPS_NODEPORT)"

port_forward_clean:
	@sudo iptables -t nat -S DOCKER | grep -- "--dport 80 -j DNAT --to-destination .*:$(INGRESS_HTTP_NODEPORT)" | sed 's/^-A /iptables -t nat -D /' | sudo sh || true; \
	sudo iptables -t nat -S DOCKER | grep -- "--dport 443 -j DNAT --to-destination .*:$(INGRESS_HTTPS_NODEPORT)" | sed 's/^-A /iptables -t nat -D /' | sudo sh || true; \
	sudo iptables -S DOCKER | grep -- "--dport $(INGRESS_HTTP_NODEPORT) -j ACCEPT" | sed 's/^-A /iptables -D /' | sudo sh || true; \
	sudo iptables -S DOCKER | grep -- "--dport $(INGRESS_HTTPS_NODEPORT) -j ACCEPT" | sed 's/^-A /iptables -D /' | sudo sh || true; \
	echo "port_forward_clean -> http=$(INGRESS_HTTP_NODEPORT) https=$(INGRESS_HTTPS_NODEPORT)"

ssh_blocklist:
	@for ip in $(SSH_BLOCKLIST_IPS); do \
		sudo iptables -C INPUT -p tcp -s $$ip --dport 22 -j DROP 2>/dev/null || sudo iptables -I INPUT 1 -p tcp -s $$ip --dport 22 -j DROP; \
	done; \
	echo "ssh_blocklist -> $(SSH_BLOCKLIST_IPS)"

ssh_blocklist_clean:
	@for ip in $(SSH_BLOCKLIST_IPS); do \
		while sudo iptables -C INPUT -p tcp -s $$ip --dport 22 -j DROP 2>/dev/null; do \
			sudo iptables -D INPUT -p tcp -s $$ip --dport 22 -j DROP; \
		done; \
	done; \
	echo "ssh_blocklist_clean -> $(SSH_BLOCKLIST_IPS)"

ssh_allowlist:
	@sudo iptables -N SSH_ALLOWLIST 2>/dev/null || true; \
	while sudo iptables -C INPUT -p tcp --dport 22 -j SSH_ALLOWLIST 2>/dev/null; do \
		sudo iptables -D INPUT -p tcp --dport 22 -j SSH_ALLOWLIST; \
	done; \
	sudo iptables -F SSH_ALLOWLIST; \
	for ip in $(SSH_ALLOWLIST_IPS); do \
		sudo iptables -A SSH_ALLOWLIST -s $$ip -p tcp --dport 22 -j ACCEPT; \
	done; \
	sudo iptables -A SSH_ALLOWLIST -p tcp --dport 22 -j REJECT --reject-with tcp-reset; \
	sudo iptables -I INPUT 1 -p tcp --dport 22 -j SSH_ALLOWLIST; \
	echo "ssh_allowlist -> $(SSH_ALLOWLIST_IPS)"

ssh_allowlist_clean:
	@while sudo iptables -C INPUT -p tcp --dport 22 -j SSH_ALLOWLIST 2>/dev/null; do \
		sudo iptables -D INPUT -p tcp --dport 22 -j SSH_ALLOWLIST; \
	done; \
	sudo iptables -F SSH_ALLOWLIST 2>/dev/null || true; \
	sudo iptables -X SSH_ALLOWLIST 2>/dev/null || true; \
	echo "ssh_allowlist_clean"

wlan0_down:
	@sudo ip link set wlan0 down 2>/dev/null || sudo ifconfig wlan0 down; \
	echo "wlan0_down"; \
	ip route; \
	echo; \
	ip addr show wlan0 2>/dev/null || ifconfig wlan0 || true

wlan0_up:
	@sudo ip link set wlan0 up 2>/dev/null || sudo ifconfig wlan0 up; \
	echo "wlan0_up"; \
	ip route; \
	echo; \
	ip addr show wlan0 2>/dev/null || ifconfig wlan0 || true

helm_repo-c:
	helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
	helm repo add istio https://istio-release.storage.googleapis.com/charts
	helm repo add prometheus https://prometheus-community.github.io/helm-charts
	helm repo add grafana https://grafana.github.io/helm-charts
	helm repo add kiali https://kiali.org/helm-charts
	helm repo add jetstack https://charts.jetstack.io
	helm repo add argo https://argoproj.github.io/argo-helm
	helm repo add phntom https://phntom.kix.co.il/charts/
	helm repo add oauth2-proxy https://oauth2-proxy.github.io/manifests

	helm repo update

namespace-c:
	kubectl apply -f ./cluster/namespaces.yaml

config-c:
# set default namespace
	kubectl config set-context --current --namespace=cluster || true
# install git secret
	kubectl create secret generic git-secret -n cluster --from-file=${HOME}/.ssh/id_rsa || true

default-tls-c:
	kubectl create secret tls default-tls -n cluster --cert=./cert/fullchain.pem --key=./cert/privkey.pem || true
default-tls-d:
	kubectl delete secret default-tls -n cluster || true
argocd-c:
	helm upgrade -i argocd argo/argo-cd -n cluster -f ./apps/argocd/values.yaml
	@sed 's/argocd.anyflow.net/${DOMAIN_ARGOCD}/' ./apps/argocd/httproute.yaml | kubectl apply -f -
argocd-d:
	helm uninstall argocd
	kubectl delete -f ./apps/argocd/httproute.yaml
argocd-l:
	argocd login argocd.anyflow.net --username admin --password ${ARGOCD_PASSWORD} --insecure
argocd-cli-c:
	VERSION=$(curl --silent "https://api.github.com/repos/argoproj/argo-cd/releases/latest" | grep -Po '"tag_name": "\K.*?(?=")')
	curl -sSL -o argocd-linux-amd64 "https://github.com/argoproj/argo-cd/releases/download/$VERSION/argocd-linux-amd64"
	chmod +x argocd-linux-amd64
	sudo mv argocd-linux-amd64 /usr/local/bin/argocd

istio-sidecar-c:
	kubectl apply -f ./cluster/namespaces.sidecar.yaml
	helm upgrade -i istio-base istio/base -n istio-system  --set defaultRevision=$(ISTIO_REVISION) --create-namespace --wait
	helm upgrade -i istiod istio/istiod -n istio-system -f ./cluster/values.sidecar.yaml --version $(ISTIO_VERSION)
	helm upgrade -i public-gateway istio/gateway -n cluster -f ./cluster/values.ingressgateway.yaml --version $(ISTIO_VERSION)
	kubectl apply -f ./cluster/telemetry.yaml
	kubectl apply -f ./cluster/wasmplugin.openapi-endpoint-filter.yaml
	kubectl apply -f ./cluster/wasmplugin.baggage-filter.yaml

istio-ambient-c:
	kubectl apply -f $(GATEWAY_API_STANDARD_INSTALL)
	kubectl apply -f ./cluster/namespaces.ambient.yaml
	helm upgrade -i istio-base istio/base -n istio-system --set defaultRevision=$(ISTIO_REVISION) --create-namespace --wait
	helm upgrade -i istiod istio/istiod -n istio-system -f ./cluster/values.ambient.yaml --version $(ISTIO_VERSION) --set profile=ambient --wait
	helm upgrade -i istio-cni istio/cni -n istio-system  --set defaultRevision=$(ISTIO_REVISION) --set profile=ambient --wait
	helm upgrade -i ztunnel istio/ztunnel -n istio-system --set defaultRevision=$(ISTIO_REVISION) --wait
	helm upgrade -i public-gateway istio/gateway -n cluster -f ./cluster/values.ingressgateway.yaml --version $(ISTIO_VERSION)
	kubectl apply -f ./cluster/telemetry.yaml
	kubectl apply -f ./cluster/waypoints.yaml
	kubectl apply -f ./cluster/wasmplugin.openapi-endpoint-filter.yaml
	kubectl apply -f ./cluster/wasmplugin.baggage-filter.yaml

gateway-c:
	kubectl apply -f $(GATEWAY_API_STANDARD_INSTALL)
#	kubectl apply -f ./cluster/wasmplugin.openapi-endpoint-filter.yaml
#	kubectl apply -f ./cluster/wasmplugin.baggage-filter.yaml
# install ingress
# 	kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
# 	@echo "Waiting maximum 300s for ingress controller to be ready ..."
# 	kubectl wait pods -n ingress-nginx -l app.kubernetes.io/component=controller --for condition=Ready --timeout=300s

staffonly-c:
	kubectl apply -k apps/staffonly/deployment
staffonly-d:
	kubectl delete -k apps/staffonly/deployment
staffonly-e:
	@POD_NAME=$$(kubectl get pods -n service | grep '^staffonly' | awk '{print $$1}' | head -n 1); \
	if [ -z "$$POD_NAME" ]; then \
		echo "No pod found with prefix 'staffonly' in namespace 'service'"; \
		exit 1; \
	else \
		echo "Executing zsh in pod: $$POD_NAME"; \
		kubectl exec -it -n service $$POD_NAME -- zsh; \
	fi

__create_dir:
	test -d $$CREATE_DIR_TARGET || sudo mkdir $$CREATE_DIR_TARGET; \
	sudo chown -R 1000:1000 $$CREATE_DIR_TARGET; \
	sudo chmod -R 700 $$CREATE_DIR_TARGET

docserver-c:
	kubectl apply -k ./apps/docserver/deployment
docserver-d:
	kubectl delete -k ./apps/docserver/deployment
docserver-r: docserver-d docserver-c


dockebi-c:
	kubectl apply -k ./apps/dockebi/deployment
dockebi-d:
	kubectl delete -k ./apps/dockebi/deployment
dockebi-r: dockebi-d dockebi-c

prometheus-c: cert_manager-c
	kubectl apply -f ./cluster/public-gateway.yaml
	kubectl apply -f ./certificate/prometheus-anyflow-net.yaml
	kubectl wait --for=condition=Ready certificate/prometheus-anyflow-net -n cluster --timeout=600s
	helm upgrade -i prometheus prometheus/prometheus -n observability -f ./apps/prometheus/values.yaml --version $(PROMETHEUS_CHART_VERSION)
	kubectl apply -f ./apps/prometheus/httproute.yaml
	kubectl apply -f ${PROMETHEUS_POD_MONITORS_CRD}
	kubectl apply -f ${PROMETHEUS_SERVICE_MONITORS_CRD}
	kubectl wait --namespace observability \
				--for=condition=ready pod \
				--selector=app.kubernetes.io/name=prometheus \
				--timeout=300s
prometheus-d:
	kubectl delete -f ${PROMETHEUS_POD_MONITORS_CRD} || true
	kubectl delete -f ${PROMETHEUS_SERVICE_MONITORS_CRD} || true
	helm uninstall prometheus -n observability || true
	kubectl delete -f ./apps/prometheus/httproute.yaml || true
	kubectl delete -f ./certificate/prometheus-anyflow-net.yaml || true
	kubectl wait --namespace observability \
				--for=condition=ready pod \
				--selector=app.kubernetes.io/name=prometheus \
				--timeout=300s
prometheus-r: prometheus-d prometheus-c

grafana-c: cert_manager-c
	kubectl apply -f ./cluster/public-gateway.yaml
	kubectl apply -f ./certificate/grafana-anyflow-net.yaml
	kubectl wait --for=condition=Ready certificate/grafana-anyflow-net -n cluster --timeout=600s
	helm upgrade -i grafana grafana/grafana -n observability -f ./apps/grafana/values.yaml --version $(GRAFANA_CHART_VERSION)
	kubectl apply -f ./apps/grafana/httproute.yaml
	kubectl wait --namespace observability \
				--for=condition=ready pod \
				--selector=app.kubernetes.io/name=grafana \
				--timeout=300s
grafana-d:
	helm uninstall grafana -n observability || true
	kubectl delete -f ./apps/grafana/httproute.yaml || true
	kubectl delete -f ./certificate/grafana-anyflow-net.yaml || true

tempo-c:
	helm upgrade -i tempo grafana/tempo -n observability -f ./apps/tempo/values.yaml --version $(TEMPO_CHART_VERSION)
	kubectl label service tempo -n observability istio.io/use-waypoint=none --overwrite
	kubectl rollout status statefulset/tempo -n observability --timeout=300s
tempo-d:
	helm uninstall tempo -n observability || true
tempo-r: tempo-d tempo-c

kiali-c: cert_manager-c
	kubectl apply -f ./cluster/public-gateway.yaml
	kubectl apply -f ./certificate/kiali-anyflow-net.yaml
	kubectl wait --for=condition=Ready certificate/kiali-anyflow-net -n cluster --timeout=600s
	helm upgrade -i -n istio-system kiali-server kiali/kiali-server -f ./apps/kiali/values.yaml --version $(KIALI_CHART_VERSION)
	kubectl apply -f apps/kiali/httproute.yaml
	kubectl apply -f apps/kiali/destinationrule.yaml
	kubectl rollout status deployment/kiali -n istio-system --timeout=300s
kiali-d:
	kubectl delete -f apps/kiali/httproute.yaml || true
	kubectl delete -f apps/kiali/destinationrule.yaml || true
	kubectl delete -f ./certificate/kiali-anyflow-net.yaml || true
	helm uninstall kiali-server -n istio-system || true
kiali-r: kiali-d kiali-c


otel-c:
	helm upgrade -n observability -i opentelemetry-operator open-telemetry/opentelemetry-operator \
	 --version $(OTEL_OPERATOR_CHART_VERSION) \
	--set "manager.collectorImage.repository=otel/opentelemetry-collector-contrib" \
	--set admissionWebhooks.certManager.enabled=false \
	--set admissionWebhooks.autoGenerateCert.enabled=true
	kubectl apply -f apps/otel/rbac.yaml
	kubectl rollout status deployment/opentelemetry-operator -n observability --timeout=300s
otel-d:
	kubectl delete -f apps/otel/rbac.yaml || true
	helm uninstall opentelemetry-operator -n observability

otel-prometheus-c:
	kubectl apply -f apps/otel/prometheus.yaml
otel-prometheus-d:
	kubectl delete -f apps/otel/prometheus.yaml

otel-cluster-c:
	kubectl apply -f apps/otel/cluster.yaml
otel-cluster-d:
	kubectl delete -f apps/otel/cluster.yaml

otel-otlp-c:
	kubectl apply -f apps/otel/otlp.yaml
otel-otlp-d:
	kubectl delete -f apps/otel/otlp.yaml
otel-otlp-r: otel-otlp-d otel-otlp-c

otel-node-c:
	kubectl apply -f apps/otel/node.yaml
otel-node-d:
	kubectl delete -f apps/otel/node.yaml


cert_manager-c:
	helm upgrade -i cert-manager jetstack/cert-manager 	--namespace cert-manager 	--create-namespace 	--version v1.20.1 	-f ./apps/cert-manager/values.yaml 	--wait
	kubectl apply -f ./certificate/issuer.yaml

cert_manager-d:
	kubectl delete -f ./certificate/issuer.yaml || true
	helm uninstall cert-manager -n cert-manager || true

api-tls-c:
	kubectl apply -f ./cluster/public-gateway.yaml
	kubectl apply -f ./certificate/api-anyflow-net.yaml
	kubectl wait --for=condition=Ready certificate/api-anyflow-net -n cluster --timeout=600s

api-tls-d:
	kubectl delete -f ./certificate/api-anyflow-net.yaml || true
	kubectl delete -f ./cluster/public-gateway.yaml || true


metric-server-c:
	@kubectl -n kube-system get deployment metrics-server >/dev/null 2>&1 || \
	kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
	@kubectl -n kube-system get deployment metrics-server -o jsonpath='{.spec.template.spec.containers[0].args}' | grep -q -- '--kubelet-insecure-tls' || \
	kubectl patch deployment metrics-server -n kube-system --type='json' \
	-p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
	@kubectl -n kube-system rollout status deploy/metrics-server --timeout=180s

docker_registry-c:
	export CREATE_DIR_TARGET="./nodes/worker0/var/local-path-provisioner/docker-registry"; \
	$(MAKE) __create_dir

	kubectl apply -f ./apps/docker-registry/pv.yaml
	kubectl apply -f ./apps/docker-registry/pvc.yaml

	helm upgrade -i docker-registry phntom/docker-registry  -n cluster -f ./apps/docker-registry/values.yaml
	@sed 's/docker-registry.anyflow.net/${DOMAIN_DOCKER_REGISTRY}/' ./apps/docker-registry/httproute.yaml | kubectl apply -f -
docker_registry-d:
	helm uninstall docker-registry -n cluster
	kubectl delete -f ./apps/docker-registry/httproute.yaml


istioctl-i:
	curl -L https://istio.io/downloadIstio | ISTIO_VERSION=$(ISTIO_VERSION) sh - && \
		sudo mv -f $(ISTIO_DIST_DIR)/bin/istioctl /usr/local/bin/istioctl && \
		sudo mv $(ISTIO_DIST_DIR)/tools/_istioctl ~/_istioctl && \
		rm -rf $(ISTIO_DIST_DIR) && \
		chmod +x /usr/local/bin/istioctl

kagent-c: cert_manager-c oauth2-proxy-c
	kubectl apply -f ./apps/kagent/secret.dummy.yaml
	@test -f ./apps/kagent/secret.grafana-mcp.yaml || (echo "missing apps/kagent/secret.grafana-mcp.yaml" >&2; exit 1)
	kubectl apply -f ./apps/kagent/secret.grafana-mcp.yaml
	$(MAKE) kmcp-d
	helm upgrade -i kagent-crds oci://ghcr.io/kagent-dev/kagent/helm/kagent-crds -n kagent --create-namespace --version $(KAGENT_CHART_VERSION)
	helm upgrade -i kagent oci://ghcr.io/kagent-dev/kagent/helm/kagent -n kagent --create-namespace -f ./apps/kagent/values.yaml --version $(KAGENT_CHART_VERSION) --wait
	kubectl set image deployment/kagent-grafana-mcp -n kagent grafana-mcp=$(KAGENT_GRAFANA_MCP_IMAGE)
	kubectl rollout status deployment/kagent-grafana-mcp -n kagent --timeout=300s
	kubectl apply -f ./apps/kagent/agentgateway-services.yaml
	kubectl apply -f ./apps/kagent/referencegrant-agentgateway.yaml
	kubectl apply -f ./cluster/public-gateway.yaml
	kubectl apply -f ./certificate/kagent-anyflow-net.yaml
	kubectl wait --for=condition=Ready certificate/kagent-anyflow-net -n cluster --timeout=600s
	kubectl apply -f ./apps/kagent/httproute.yaml
	kubectl delete authorizationpolicy public-gateway-kagent-authelia -n cluster --ignore-not-found
	kubectl apply -f ./apps/kagent/authzpolicy.yaml
	kubectl rollout status deployment/kagent-controller -n kagent --timeout=300s
	$(MAKE) kmcp-c

kagent-d:
	kubectl delete -f ./apps/kagent/authzpolicy.yaml || true
	kubectl delete -f ./apps/kagent/httproute.yaml || true
	kubectl delete -f ./certificate/kagent-anyflow-net.yaml || true
	kubectl delete -f ./apps/kagent/referencegrant-agentgateway.yaml || true
	kubectl delete -f ./apps/kagent/agentgateway-services.yaml || true
	$(MAKE) kmcp-d
	helm uninstall kagent -n kagent || true
	helm uninstall kagent-crds -n kagent || true
	kubectl delete -f ./apps/kagent/secret.dummy.yaml || true
	kubectl delete -f ./apps/kagent/secret.grafana-mcp.yaml || true

kmcp-c:
	@echo "kmcp is bundled with kagent; ensuring bundled controller is ready"
	kubectl rollout status deployment/kagent-kmcp-controller-manager -n kagent --timeout=300s

kmcp-d:
	@echo "removing legacy standalone kmcp releases if present"
	helm uninstall kmcp -n kagent || true
	helm uninstall kmcp-crds -n kagent || true

agentgateway-c: kagent-c
	@test -f ./apps/agentgateway/secret.openai.yaml || (echo "missing apps/agentgateway/secret.openai.yaml" >&2; exit 1)
	kubectl apply -f ./apps/agentgateway/secret.openai.yaml
	helm upgrade -i agentgateway-crds oci://cr.agentgateway.dev/charts/agentgateway-crds --create-namespace --namespace agentgateway-system --version $(AGENTGATEWAY_CHART_VERSION) --set controller.image.pullPolicy=Always
	helm upgrade -i agentgateway oci://cr.agentgateway.dev/charts/agentgateway --namespace agentgateway-system --version $(AGENTGATEWAY_CHART_VERSION) -f ./apps/agentgateway/values.yaml --wait
	kubectl apply -f ./apps/agentgateway/gateway.proxy.yaml
	kubectl wait --for=jsonpath='{.status.conditions[?(@.type=="Programmed")].status}'=True gateway/agentgateway-proxy -n agentgateway-system --timeout=300s
	kubectl apply -f ./apps/agentgateway/httproute.kagent.yaml
	kubectl apply -f ./apps/agentgateway/agentgatewaybackend.openai.yaml
	kubectl apply -f ./cluster/public-gateway.yaml
	kubectl apply -f ./certificate/agentgateway-anyflow-net.yaml
	kubectl wait --for=condition=Ready certificate/agentgateway-anyflow-net -n cluster --timeout=600s
	kubectl patch deployment agentgateway-proxy -n agentgateway-system --type=strategic -p '{"spec":{"template":{"spec":{"containers":[{"name":"admin-ui-proxy","image":"alpine/socat:latest","args":["TCP-LISTEN:15001,fork,reuseaddr,bind=0.0.0.0","TCP:127.0.0.1:15000"],"ports":[{"containerPort":15001,"name":"admin-ui","protocol":"TCP"}]}]}}}}'
	kubectl rollout status deployment/agentgateway-proxy -n agentgateway-system --timeout=300s
	kubectl apply -f ./apps/agentgateway/service.agentgateway-admin.yaml
	kubectl apply -f ./apps/agentgateway/httproute.agentgateway-admin.yaml
	kubectl delete authorizationpolicy public-gateway-agentgateway-authelia -n cluster --ignore-not-found
	kubectl apply -f ./apps/agentgateway/authorizationpolicy.agentgateway-admin.yaml
	kubectl rollout status deployment/agentgateway -n agentgateway-system --timeout=300s
	kubectl rollout status deployment/agentgateway-proxy -n agentgateway-system --timeout=300s
	$(MAKE) stock-mcp-c
	$(MAKE) stock-agent-c

agentgateway-d:
	$(MAKE) stock-agent-d
	$(MAKE) stock-mcp-d
	kubectl delete -f ./apps/agentgateway/authorizationpolicy.agentgateway-admin.yaml || true
	kubectl delete -f ./apps/agentgateway/httproute.agentgateway-admin.yaml || true
	kubectl delete -f ./apps/agentgateway/service.agentgateway-admin.yaml || true
	kubectl delete -f ./certificate/agentgateway-anyflow-net.yaml || true
	kubectl delete -f ./apps/agentgateway/agentgatewaybackend.openai.yaml || true
	kubectl delete -f ./apps/agentgateway/httproute.kagent.yaml || true
	kubectl delete -f ./apps/agentgateway/gateway.proxy.yaml || true
	helm uninstall agentgateway -n agentgateway-system || true
	helm uninstall agentgateway-crds -n agentgateway-system || true
	kubectl delete -f ./apps/agentgateway/secret.openai.yaml || true


authelia-c: cert_manager-c
	@test -f ./apps/authelia/secret.yaml || (echo "missing apps/authelia/secret.yaml" >&2; exit 1)
	kubectl apply -f ./apps/authelia/secret.yaml
	kubectl apply -f ./apps/authelia/deployment.yaml
	kubectl rollout status deployment/authelia -n cluster --timeout=300s
	kubectl apply -f ./apps/authelia/auth-httproute.yaml
	kubectl apply -f ./apps/authelia/logout-httproute.yaml

authelia-d:
	kubectl delete -f ./apps/authelia/logout-httproute.yaml || true
	kubectl delete -f ./apps/authelia/auth-httproute.yaml || true
	kubectl delete -f ./apps/authelia/deployment.yaml || true
	kubectl delete secret authelia-config -n cluster || true

oauth2-proxy-c: authelia-c
	@test -f ./apps/oauth2-proxy/secret.yaml || (echo "missing apps/oauth2-proxy/secret.yaml" >&2; exit 1)
	kubectl apply -f ./apps/oauth2-proxy/secret.yaml
	helm repo add oauth2-proxy https://oauth2-proxy.github.io/manifests
	helm upgrade -i oauth2-proxy oauth2-proxy/oauth2-proxy -n cluster --version $(OAUTH2_PROXY_CHART_VERSION) -f ./apps/oauth2-proxy/values.yaml --wait
	kubectl apply -f ./apps/oauth2-proxy/referencegrant-agentgateway.yaml
	kubectl rollout status deployment/oauth2-proxy -n cluster --timeout=300s

oauth2-proxy-d:
	kubectl delete -f ./apps/oauth2-proxy/referencegrant-agentgateway.yaml || true
	helm uninstall oauth2-proxy -n cluster || true
	kubectl delete deployment oauth2-proxy -n cluster --ignore-not-found || true
	kubectl delete service oauth2-proxy -n cluster --ignore-not-found || true
	kubectl delete configmap oauth2-proxy oauth2-proxy-config -n cluster --ignore-not-found || true
	kubectl delete -f ./apps/oauth2-proxy/secret.yaml || true


anyflow-blog-c: cert_manager-c
	kubectl apply -f ./cluster/public-gateway.yaml
	kubectl apply -f ./certificate/blog-anyflow-net.yaml
	kubectl wait --for=condition=Ready certificate/blog-anyflow-net -n cluster --timeout=600s
	$(MAKE) -C apps/anyflow-blog create
anyflow-blog-d:
	$(MAKE) -C apps/anyflow-blog delete
	kubectl delete -f ./certificate/blog-anyflow-net.yaml || true
anyflow-blog-r: anyflow-blog-d anyflow-blog-c


stock-mcp-image-c:
	$(MAKE) -C apps/market-reporter image-c

stock-mcp-common-c: stock-mcp-image-c
	kubectl apply -f ./apps/kagent/custom/stock-mcp.yaml
	kubectl delete remotemcpserver market-intelligence-mcp -n kagent --ignore-not-found
	kubectl rollout status deployment/stock-mcp -n kagent --timeout=300s

stock-mcp-common-d:
	kubectl delete mcpserver market-intelligence-mcp -n kagent --ignore-not-found
	kubectl delete remotemcpserver market-intelligence-mcp -n kagent --ignore-not-found
	kubectl delete -f ./apps/kagent/custom/stock-mcp.yaml || true

stock-mcp-tesla-c: stock-mcp-common-c
	kubectl apply -f ./apps/kagent/custom/tesla-stock-agent.yaml
	kubectl apply -f ./apps/kagent/custom/tesla-stock-daily-report.yaml
	kubectl rollout status deployment/tesla-stock-agent -n kagent --timeout=300s
	kubectl delete agent tesla-intelligence-analyst -n kagent --ignore-not-found
	kubectl delete cronjob tesla-market-intelligence-daily-report -n kagent --ignore-not-found

stock-mcp-tesla-d:
	kubectl delete -f ./apps/kagent/custom/tesla-stock-daily-report.yaml || true
	kubectl delete -f ./apps/kagent/custom/tesla-stock-agent.yaml || true
	kubectl delete agent tesla-intelligence-analyst -n kagent --ignore-not-found
	kubectl delete cronjob tesla-market-intelligence-daily-report -n kagent --ignore-not-found

stock-mcp-samsung-c: stock-mcp-common-c
	kubectl apply -f ./apps/kagent/custom/samsung-stock-agent.yaml
	kubectl apply -f ./apps/kagent/custom/samsung-stock-daily-report.yaml
	kubectl rollout status deployment/samsung-stock-agent -n kagent --timeout=300s
	kubectl delete agent samsung-electronics-intelligence-analyst -n kagent --ignore-not-found
	kubectl delete cronjob samsung-electronics-market-intelligence-daily-report -n kagent --ignore-not-found

stock-mcp-samsung-d:
	kubectl delete -f ./apps/kagent/custom/samsung-stock-daily-report.yaml || true
	kubectl delete -f ./apps/kagent/custom/samsung-stock-agent.yaml || true
	kubectl delete agent samsung-electronics-intelligence-analyst -n kagent --ignore-not-found
	kubectl delete cronjob samsung-electronics-market-intelligence-daily-report -n kagent --ignore-not-found

stock-mcp-c: stock-mcp-tesla-c stock-mcp-samsung-c
	kubectl delete mcpserver market-intelligence-mcp -n kagent --ignore-not-found

stock-mcp-d: stock-mcp-samsung-d stock-mcp-tesla-d stock-mcp-common-d

stock-mcp-r: stock-mcp-d stock-mcp-c

stock-agent-c:
	kubectl apply -f ./apps/kagent/custom/stock-agent.yaml
	kubectl rollout status deployment/stock-agent -n kagent --timeout=300s

stock-agent-d:
	kubectl delete -f ./apps/kagent/custom/stock-agent.yaml || true

stock-agent-r: stock-agent-d stock-agent-c
