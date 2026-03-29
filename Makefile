include .env

export

create-sidecar: init
	$(MAKE) enlarge_open_file_count
	$(MAKE) port_forward
	$(MAKE) istio-sidecar
	$(MAKE) app

create-ambient: init
	$(MAKE) enlarge_open_file_count
	$(MAKE) port_forward
	$(MAKE) istio-ambient
	$(MAKE) app
INGRESS_HTTP_NODEPORT ?= 30080
INGRESS_HTTPS_NODEPORT ?= 30443
GATEWAY_API_VERSION ?= v1.5.1
GATEWAY_API_STANDARD_INSTALL ?= https://github.com/kubernetes-sigs/gateway-api/releases/download/$(GATEWAY_API_VERSION)/standard-install.yaml
KIALI_CHART_VERSION ?= 2.23.0
PROMETHEUS_CHART_VERSION ?= 28.14.1
GRAFANA_CHART_VERSION ?= 10.5.15
OTEL_OPERATOR_CHART_VERSION ?= 0.109.0

init: cluster-c helm_repo-c
istio-sidecar: istio-sidecar-c config-c gateway-c cert_manager-c api-tls-c
istio-ambient: istio-ambient-c config-c gateway-c cert_manager-c api-tls-c
app: docserver-c dockebi-c
observability:  prometheus-c grafana-c otel-c otel-prometheus-c jaeger-c kiali-c
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

helm_repo-c:
	helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
	helm repo add istio https://istio-release.storage.googleapis.com/charts
	helm repo add prometheus https://prometheus-community.github.io/helm-charts
	helm repo add grafana https://grafana.github.io/helm-charts
	helm repo add kiali https://kiali.org/helm-charts
	helm repo add jaeger https://jaegertracing.github.io/helm-charts
	helm repo add jetstack https://charts.jetstack.io
	helm repo add argo https://argoproj.github.io/argo-helm
	helm repo add phntom https://phntom.kix.co.il/charts/

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
	helm upgrade -i istio-base istio/base -n istio-system  --set defaultRevision=1.29.1 --create-namespace --wait
	helm upgrade -i istiod istio/istiod -n istio-system -f ./cluster/values.sidecar.yaml --version 1.29.1
	helm upgrade -i istio-ingressgateway istio/gateway -n cluster -f ./cluster/values.ingressgateway.yaml --version 1.29.1
	kubectl apply -f ./cluster/telemetry.yaml
	kubectl apply -f ./cluster/wasmplugin.openapi-endpoint-filter.yaml
	kubectl apply -f ./cluster/wasmplugin.baggage-filter.yaml

istio-ambient-c:
	kubectl apply -f $(GATEWAY_API_STANDARD_INSTALL)
	kubectl apply -f ./cluster/namespaces.ambient.yaml
	helm upgrade -i istio-base istio/base -n istio-system --set defaultRevision=1.29.1 --create-namespace --wait
	helm upgrade -i istiod istio/istiod -n istio-system -f ./cluster/values.ambient.yaml --version 1.29.1 --set profile=ambient --wait
	helm upgrade -i istio-cni istio/cni -n istio-system  --set defaultRevision=1.29.1 --set profile=ambient --wait
	helm upgrade -i ztunnel istio/ztunnel -n istio-system --set defaultRevision=1.29.1 --wait
	helm upgrade -i istio-ingressgateway istio/gateway -n cluster -f ./cluster/values.ingressgateway.yaml --version 1.29.1
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

PROMETHEUS_POD_MONITORS_CRD := https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.72.0/example/prometheus-operator-crd/monitoring.coreos.com_podmonitors.yaml
PROMETHEUS_SERVICE_MONITORS_CRD := https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.72.0/example/prometheus-operator-crd/monitoring.coreos.com_servicemonitors.yaml

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

jaeger-c:
	helm upgrade -i -n observability jaeger jaeger/jaeger -f ./apps/jaeger/values.yaml --version 3.4.1
	kubectl apply -f ./apps/jaeger/httproute.yaml
jaeger-d:
	helm uninstall jaeger -n observability
	kubectl delete -f ./apps/jaeger/httproute.yaml
jaeger-r: jaeger-d jaeger-c

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
	kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
	kubectl patch deployment metrics-server -n kube-system --type='json' \
  -p '[{"op":"add", "path":"/spec/template/spec/containers/0/args/-", "value":"--kubelet-insecure-tls"}]'

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
	curl -L https://istio.io/downloadIstio | sh - && \
		sudo mv -f istio-1.29.1/bin/istioctl /usr/local/bin/istioctl && \
		sudo mv istio-1.29.1/tools/_istioctl ~/_istioctl && \
		rm -rf istio-1.29.1 && \
		chmod +x /usr/local/bin/istioctl
