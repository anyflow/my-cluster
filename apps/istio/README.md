# Prometheus `values.yaml`

## Chart Repository

- `helm repo add istio https://istio-release.storage.googleapis.com/charts`
- **README.md** : <https://github.com/istio/istio/tree/master/manifests/charts/istio-control/istio-discovery>

## ArgoCD application manifest (for `kic-st`)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kic-st-istio
spec:
    project: cluster
    source:
      repoURL: 'https://istio-release.storage.googleapis.com/charts'
      targetRevision: 1.18.2
      chart: istiod
    destination:
      namespace: ns-observability
      name: kic-st-cluster
    sources:
      - repoURL: 'https://istio-release.storage.googleapis.com/charts'
        targetRevision: 1.18.2
        chart: istiod
        helm:
          valueFiles:
            - $values/istio/kic-st.values.yaml
      - repoURL: 'http://gitea.lgthinq.com/cluster/helm-charts.git'
        targetRevision: main
        ref: values
```
