# Prometheus `values.yaml`

## Chart Repository

- <https://kiali.org/helm-charts>
- **README.md**: <https://github.com/kiali/helm-charts>
- **CR Reference**: <https://kiali.io/docs/configuration/kialis.kiali.io/#.spec.server.observability.tracing.otel>

## ArgoCD application manifest (for `kic-st`)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kic-st-kiali
spec:
 project: cluster
 source:
   repoURL: 'https://kiali.org/helm-charts'
   targetRevision: 1.72.0
   chart: kiali-server
 destination:
   namespace: ns-observability
   name: kic-st-cluster
 sources:
   - repoURL: 'https://kiali.org/helm-charts'
     targetRevision: 1.72.0
     helm:
       valueFiles:
         - $values/kiali/kic-st.values.yaml
     chart: kiali-server
   - repoURL: 'http://gitea.lgthinq.com/cluster/helm-charts.git'
     targetRevision: main
     ref: values
```
