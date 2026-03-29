# cert-manager `values.yaml`

## Chart Repository

- `helm repo add jetstack https://charts.jetstack.io`
- **README.md**: <https://cert-manager.io/docs/installation/helm/>
- **Chart**: <https://artifacthub.io/packages/helm/cert-manager/cert-manager>

## Install

```sh
helm upgrade -i cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.20.1 \
  -f ./apps/cert-manager/values.yaml \
  --wait
```

## Notes

- `crds.enabled=true` keeps the CRD installation aligned with this chart install.
- `config.enableGatewayAPI=true` enables the Gateway API HTTP-01 solver path used in this cluster.
