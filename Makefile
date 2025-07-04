include .env

export

create-sidecar: init istio-sidecar app otel
create-ambient: init istio-ambient app otel

# WARN
# kind version 0.27에서는 ambient mode 정상 동작하지 않음(ztunnel 설치 실패 - coreDNS crash 등)

onetime: port_forward enlarge_open_file_count
init: cluster-c helm_repo-c
istio-sidecar: istio-sidecar-c metallb-c config-c gateway-c
istio-ambient: istio-ambient-c metallb-c config-c gateway-c
app: docserver-c dockebi-c prometheus-c grafana-c otel-c jaeger-c kiali-c
otel: otel-otlp-c otel-prometheus-c


cluster-c:
	kind create cluster --config ./kind-config.yaml
cluster-d:
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
	sudo iptables -A DOCKER -p tcp -s 0.0.0.0/0 -d 172.18.255.200 --dport 80 -j ACCEPT
	sudo iptables -t nat -A DOCKER -p tcp --dport 80 -j DNAT --to-destination 172.18.255.200:80
	sudo iptables -t nat -A POSTROUTING -s 172.18.255.200 -d 172.18.255.200 -p tcp --dport 80 -j MASQUERADE

	sudo iptables -A DOCKER -p tcp -s 0.0.0.0/0 -d 172.18.255.200 --dport 443 -j ACCEPT
	sudo iptables -t nat -A DOCKER -p tcp --dport 443 -j DNAT --to-destination 172.18.255.200:443
	sudo iptables -t nat -A POSTROUTING -s 172.18.255.200 -d 172.18.255.200 -p tcp --dport 443 -j MASQUERADE

metallb-c:
	kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.7/config/manifests/metallb-native.yaml
	kubectl wait --namespace metallb-system \
					--for=condition=ready pod \
					--selector=app=metallb \
					--timeout=180s

helm_repo-c:
	helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
	helm repo add istio https://istio-release.storage.googleapis.com/charts
	helm repo add prometheus https://prometheus-community.github.io/helm-charts
	helm repo add grafana https://grafana.github.io/helm-charts
	helm repo add kiali https://kiali.org/helm-charts
	helm repo add jaeger https://jaegertracing.github.io/helm-charts
	helm repo add jenkins https://charts.jenkins.io
	helm repo add argo https://argoproj.github.io/argo-helm
	helm repo add bitnami https://charts.bitnami.com/bitnami
	helm repo add elastic https://helm.elastic.co
	helm repo add phntom https://phntom.kix.co.il/charts/

	helm repo update

namespace-c:
	kubectl apply -f ./cluster/namespaces.yaml

config-c:
# set default namespace
	kubectl config set-context --current --namespace=cluster || true
# install default tls secret
	kubectl create secret tls default-tls -n cluster --cert=./cert/fullchain.pem --key=./cert/privkey.pem || true
# install git secret
	kubectl create secret generic git-secret -n cluster --from-file=${HOME}/.ssh/id_rsa
# set metallb config
	kubectl apply -f ./cluster/metallb-config.yaml || true

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
	helm upgrade -i istio-base istio/base -n istio-system  --set defaultRevision=1.26.0 --create-namespace --wait
	helm upgrade -i istiod istio/istiod -n istio-system -f ./cluster/values.sidecar.yaml --version 1.26.0
	helm upgrade -i istio-ingressgateway istio/gateway -n cluster --set service.type=LoadBalancer --version 1.26.0
	kubectl apply -f ./cluster/telemetry.yaml
	kubectl apply -f ./cluster/wasmplugin.openapi-endpoint-filter.yaml
	kubectl apply -f ./cluster/wasmplugin.baggage-filter.yaml

istio-ambient-c:
	kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/standard-install.yaml
	helm upgrade -i istio-base istio/base -n istio-system --set defaultRevision=1.26.0 --create-namespace --wait
	helm upgrade -i istiod istio/istiod -n istio-system -f ./cluster/values.ambient.yaml --version 1.26.0 --set profile=ambient --wait
	helm upgrade -i istio-cni istio/cni -n istio-system  --set defaultRevision=1.26.0 --set profile=ambient --wait
	helm upgrade -i ztunnel istio/ztunnel -n istio-system --set defaultRevision=1.26.0 --wait
	helm upgrade -i istio-ingressgateway istio/gateway -n cluster --set service.type=LoadBalancer --version 1.26.0
	kubectl apply -f ./cluster/namespaces.ambient.yaml
	kubectl apply -f ./cluster/telemetry.yaml
	kubectl apply -f ./cluster/waypoints.yaml
	kubectl apply -f ./cluster/wasmplugin.openapi-endpoint-filter.yaml
	kubectl apply -f ./cluster/wasmplugin.baggage-filter.yaml

gateway-c:
	kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/standard-install.yaml
	kubectl apply -f ./cluster/gateway.yaml || true
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

prometheus-c:
	helm upgrade -i prometheus prometheus/prometheus -n observability -f ./apps/prometheus/values.yaml
	@sed 's/prometheus.anyflow.net/${DOMAIN_PROMETHEUS}/' ./apps/prometheus/httproute.yaml | kubectl apply -f -
	kubectl apply -f ${PROMETHEUS_POD_MONITORS_CRD}
	kubectl apply -f ${PROMETHEUS_SERVICE_MONITORS_CRD}
	kubectl wait --namespace observability \
				--for=condition=ready pod \
				--selector=app.kubernetes.io/name=prometheus \
				--timeout=300s
prometheus-d:
	kubectl delete -f ${PROMETHEUS_POD_MONITORS_CRD} || true
	kubectl delete -f ${PROMETHEUS_SERVICE_MONITORS_CRD} || true
	helm uninstall prometheus
	kubectl delete -f ./apps/prometheus/httproute.yaml
	kubectl wait --namespace observability \
				--for=condition=ready pod \
				--selector=app.kubernetes.io/name=prometheus \
				--timeout=300s
prometheus-r: prometheus-d prometheus-c

grafana-c:
	helm upgrade -i grafana grafana/grafana -n observability -f ./apps/grafana/values.yaml
	@sed 's/grafana.anyflow.net/${DOMAIN_GRAFANA}/' ./apps/grafana/httproute.yaml | kubectl apply -f -
	kubectl wait --namespace observability \
				--for=condition=ready pod \
				--selector=app.kubernetes.io/name=grafana \
				--timeout=300s
grafana-d:
	helm uninstall grafana -n observability
	kubectl delete -f ./apps/grafana/httproute.yaml

jaeger-c:
	helm upgrade -i -n observability jaeger jaeger/jaeger -f ./apps/jaeger/values.yaml --version 3.4.1
	kubectl apply -f ./apps/jaeger/httproute.yaml
jaeger-d:
	helm uninstall jaeger -n observability
	kubectl delete -f ./apps/jaeger/httproute.yaml
jaeger-r: jaeger-d jaeger-c

kiali-c:
	helm upgrade -i -n istio-system kiali-server kiali/kiali-server -f ./apps/kiali/values.yaml --version 2.8.0
	kubectl apply -f apps/kiali/httproute.yaml
	kubectl apply -f apps/kiali/destinationrule.yaml
	kubectl wait --namespace istio-system \
				--for=condition=ready pod \
				--selector=app.kubernetes.io/name=kiali \
				--timeout=300s
kiali-d:
	kubectl delete -f apps/kiali/httproute.yaml
	helm uninstall kiali-server -n istio-system
kiali-r: kiali-d kiali-c


otel-c:
	helm upgrade -n observability -i opentelemetry-operator open-telemetry/opentelemetry-operator \
	 --version 0.86.4 \
	--set "manager.collectorImage.repository=otel/opentelemetry-collector-contrib" \
	--set admissionWebhooks.certManager.enabled=false \
	--set admissionWebhooks.autoGenerateCert.enabled=true
	kubectl apply -f apps/otel/rbac.yaml
	kubectl wait --namespace observability \
				--for=condition=ready pod \
				--selector=app.kubernetes.io/name=opentelemetry-operator \
				--timeout=300s
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
	kubectl create ns cert-manager || true
	kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.4/cert-manager.yaml

cert_manager-d:
	kubectl delete -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.4/cert-manager.yaml


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


eck-c:
	kubectl create ns elastic-system || true
	kubectl create -f https://download.elastic.co/downloads/eck/2.11.1/crds.yaml || true
	kubectl apply -f https://download.elastic.co/downloads/eck/2.11.1/operator.yaml || true
eck-d:
	kubectl delete -f https://download.elastic.co/downloads/eck/2.11.1/operator.yaml || true
	kubectl delete -f https://download.elastic.co/downloads/eck/2.11.1/crds.yaml || true
	kubectl delete ns elastic-system || true

elasticsearch-c:
	kubectl apply -f apps/eck/elasticsearch.yaml
	kubectl apply -f apps/eck/elasticsearch.httproute.yaml
elasticsearch-d:
	kubectl delete -f apps/eck/elasticsearch.httproute.yaml
	kubectl delete -f apps/eck/elasticsearch.yaml
elasticsearch-password:
	kubectl get secret elasticsearch-es-elastic-user -o go-template='{{.data.elastic | base64decode}}'

kibana-c:
	kubectl apply -f apps/eck/kibana.yaml || true
	kubectl apply -f apps/eck/kibana.httproute.yaml
kibana-d:
	kubectl delete -f apps/eck/kibana.httproute.yaml
	kubectl delete -f apps/eck/kibana.yaml
kibana_objects:
	curl -X POST "kibana.lgthinq.com.local/api/saved_objects/_import" -H "kbn-xsrf: true" --form file=@elasticsearch/dashboard.ndjson -H "kbn-xsrf: true"

fluentbit-c:
	helm upgrade -i fluentbit bitnami/fluent-bit -f ./apps/fluentbit/values.yaml -n cluster
fluentbit-d:
	helm uninstall fluentbit -n cluster


kafka-c:
	helm upgrade -i -n cluster kafka bitnami/kafka -f ./apps/kafka/values.yaml
kafka-d:
	helm uninstall -n cluster kafka

kafkaui-c:
	helm upgrade -i -n cluster kafkaui kafka-ui/kafka-ui -f ./apps/kafkaui/values.yaml
kafkaui-d:
	helm uninstall -n cluster kafkaui

kafka_client-c:
	kubectl run kafka-client --restart='Never' --image docker.io/bitnami/kafka:3.4.0-debian-11-r22 --namespace cluster --command -- sleep infinity
kafka_client-d:
	kubectl delete pod -n cluster kafka-client

exec_kafka_client:
	kubectl exec -it -n cluster kafka-client -- bash

jenkins-c:
	export CREATE_DIR_TARGET="./nodes/worker0/var/local-path-provisioner/jenkins"; \
	$(MAKE) __create_dir

	kubectl apply -f ./apps/jenkins/pv.yaml
	kubectl apply -f ./apps/jenkins/pvc.yaml

	helm upgrade -i jenkins jenkins/jenkins -n cluster -f ./apps/jenkins/values.yaml
	@sed 's/jenkins.anyflow.net/${DOMAIN_JENKINS}/' ./apps/jenkins/httproute.yaml | kubectl apply -f -
jenkins-d:
	helm uninstall jenkins
	kubectl delete -f ./apps/jenkins/httproute.yaml
	kubectl delete -f ./apps/jenkins/pvc.yaml
	kubectl delete -f ./apps/jenkins/pv.yaml

bookinfo-c:
	kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.25/samples/bookinfo/platform/kube/bookinfo.yaml -n service
	kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.25/samples/bookinfo/platform/kube/bookinfo-versions.yaml -n service
	kubectl apply -f apps/bookinfo/httproute.yaml
bookinfo-d:
	kubectl delete -f apps/bookinfo/httproute.yaml
	kubectl delete -f https://raw.githubusercontent.com/istio/istio/release-1.25/samples/bookinfo/platform/kube/bookinfo-versions.yaml -n service
	kubectl delete -f https://raw.githubusercontent.com/istio/istio/release-1.25/samples/bookinfo/platform/kube/bookinfo.yaml -n service

customers-c:
	kubectl apply -k ./apps/customers
customers-d:
	kubectl delete -k ./apps/customers
	kubectl delete authorizationpolicies.security.istio.io -n service allow-web-frontend-customers allow-ingress-frontend deny-all


istioctl-i:
	curl -L https://istio.io/downloadIstio | sh - && \
		sudo mv -f istio-1.26.0/bin/istioctl /usr/local/bin/istioctl && \
		sudo mv istio-1.26.0/tools/_istioctl ~/_istioctl && \
		rm -rf istio-1.26.0 && \
		chmod +x /usr/local/bin/istioctl