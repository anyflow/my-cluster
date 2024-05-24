include .env

export

initialize: cluster-c metallb-c helm_repo-c istio-c config-c port_forward


cluster-c:
	kind create cluster --config ./kind-config.yaml
cluster-d:
	kind delete cluster -n my-cluster


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


istio-c:
	kubectl create ns istio-system || true
	helm upgrade -i istio-base istio/base -n istio-system --set defaultRevision=1.22.0
	helm upgrade -i istiod istio/istiod -n istio-system -f ./apps/istio/values.yaml --version 1.22.0
istio-d:
	helm uninstall istiod -n istio-system
	helm uninstall istio-base -n istio-system
istio-r: istio-d istio-c


config-c:
# create namespace
	kubectl create ns cluster || true
# set default namespace
	kubectl config set-context --current --namespace=cluster || true
# install default tls secret
	kubectl create secret tls default-tls -n cluster --cert=./cert/fullchain.pem --key=./cert/privkey.pem || true
# set istio injection
	kubectl label namespace cluster istio-injection=enabled || true
# set metallb config
	kubectl apply -f ./cluster/metallb-config.yaml || true
# install gateway
	@if ! kubectl get crd gateways.gateway.networking.k8s.io >/dev/null 2>&1; then \
		kubectl kustomize "github.com/kubernetes-sigs/gateway-api/config/crd?ref=v1.1.0" | kubectl apply -f -; \
	fi
	kubectl apply -f ./cluster/gateway.yaml || true
# install ingress
# 	kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
# 	@echo "Waiting maximum 300s for ingress controller to be ready ..."
# 	kubectl wait pods -n ingress-nginx -l app.kubernetes.io/component=controller --for condition=Ready --timeout=300s


__create_dir:
	test -d $$CREATE_DIR_TARGET || sudo mkdir $$CREATE_DIR_TARGET; \
	sudo chown -R 1000:1000 $$CREATE_DIR_TARGET; \
	sudo chmod -R 700 $$CREATE_DIR_TARGET


staffonly-c:
	kubectl apply -k apps/staffonly/deployment
staffonly-d:
	kubectl delete -k apps/staffonly/deployment
staffonly-e:
	kubectl exec -it -n cluster staffonly -- zsh


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


docserver-c:
	kubectl apply -k ./apps/docserver/deployment/overlays/prod
docserver-d:
	kubectl delete -k ./apps/docserver/deployment/overlays/prod
docserver-r: docserver-d docserver-c


dockebi-c:
	kubectl apply -k ./apps/dockebi/deployment/overlays/prod
dockebi-d:
	kubectl delete -k ./apps/dockebi/deployment/overlays/prod
dockebi-r: dockebi-d dockebi-c

PROMETHEUS_POD_MONITORS_CRD := https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.72.0/example/prometheus-operator-crd/monitoring.coreos.com_podmonitors.yaml
PROMETHEUS_SERVICE_MONITORS_CRD := https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.72.0/example/prometheus-operator-crd/monitoring.coreos.com_servicemonitors.yaml

prometheus-c:
	helm upgrade -i prometheus prometheus/prometheus -n cluster -f ./apps/prometheus/values.yaml
	@sed 's/prometheus.anyflow.net/${DOMAIN_PROMETHEUS}/' ./apps/prometheus/httproute.yaml | kubectl apply -f -
	kubectl apply -f ${PROMETHEUS_POD_MONITORS_CRD}
	kubectl apply -f ${PROMETHEUS_SERVICE_MONITORS_CRD}
prometheus-d:
	kubectl delete -f ${PROMETHEUS_POD_MONITORS_CRD} || true
	kubectl delete -f ${PROMETHEUS_SERVICE_MONITORS_CRD} || true
	helm uninstall prometheus
	kubectl delete -f ./apps/prometheus/httproute.yaml


grafana-c:
	helm upgrade -i grafana grafana/grafana -n cluster -f ./apps/grafana/values.yaml
	@sed 's/grafana.anyflow.net/${DOMAIN_GRAFANA}/' ./apps/grafana/httproute.yaml | kubectl apply -f -
grafana-d:
	helm uninstall grafana
	kubectl delete -f ./apps/grafana/httproute.yaml


jaeger-c:
	helm upgrade -i jaeger jaeger/jaeger -n istio-system -f ./apps/jaeger/values.yaml
	@sed 's/jaeger.anyflow.net/${DOMAIN_JAEGER}/' ./apps/jaeger/httproute.yaml | kubectl apply -f -
jaeger-d:
	helm uninstall jaeger -n istio-system
	kubectl delete -f ./apps/jaeger/httproute.yaml
jaeger-r: jaeger-d jaeger-c

kiali-c:
	helm upgrade -i kiali kiali/kiali-server -n istio-system -f ./apps/kiali/values.yaml --version 1.76
	@sed 's/kiali.anyflow.net/${DOMAIN_KIALI}/' ./apps/kiali/httproute.yaml | kubectl apply -f -
kiali-d:
	helm uninstall kiali -n istio-system
	kubectl delete -f ./apps/kiali/httproute.yaml


argocd-c:
	helm upgrade -i argocd argo/argo-cd -n cluster -f ./apps/argocd/values.yaml
	@sed 's/argocd.anyflow.net/${DOMAIN_ARGOCD}/' ./apps/argocd/httproute.yaml | kubectl apply -f -
argocd-d:
	helm uninstall argocd
	kubectl delete -f ./apps/argocd/httproute.yaml


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


eck-c:
	kubectl create ns elastic-system || true
	kubectl label namespace elastic-system istio-injection=enabled || true
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



RELEASE_NAME := my-opentelemetry-operator
RELEASE_NAMESPACE := opentelemetry-operator-system
otel-c:
	helm upgrade -i opentelemetry-operator open-telemetry/opentelemetry-operator \
		--set "manager.collectorImage.repository=otel/opentelemetry-collector-k8s" -f apps/otel/values.yaml
	kubectl annotate crds instrumentations.opentelemetry.io opentelemetrycollectors.opentelemetry.io opampbridges.opentelemetry.io \
		meta.helm.sh/release-name=${RELEASE_NAME} \
		meta.helm.sh/release-namespace=${RELEASE_NAMESPACE} || true
	kubectl label crds instrumentations.opentelemetry.io opentelemetrycollectors.opentelemetry.io opampbridges.opentelemetry.io app.kubernetes.io/managed-by=Helm
otel-d:
	helm uninstall opentelemetry-operator

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
	kubectl label namespace cert-manager istio-injection=enabled || true
	kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.4/cert-manager.yaml

cert_manager-d:
	kubectl delete -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.4/cert-manager.yaml




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
