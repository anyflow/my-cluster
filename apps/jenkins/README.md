# App: Jenkins

## Key Considerations
- **Reuse of Existing User Settings (plugins, credentials, etc.) and Jobs**: This avoids the hassle of reconfiguring these with each installation. This is achieved through the section [Reuse of Existing Storage](#reuse-of-existing-storage) below.

## Settings
- **Used Helm Chart**
  - [Jenkins Helm Chart README](https://github.com/jenkinsci/helm-charts/blob/main/charts/jenkins/README.md)
- **Access Address**
  - Defined as `DOMAIN_JENKINS` in `.env`
- **Data Storage Location**
  - `/nodes/worker0/var/local-path-provisioner/jenkins`
- **Relevant Commands in [Makefile](../../Makefile)**
  - Create: `make jenkins-c`
  - Delete: `make jenkins-d`

## Reuse of Existing Storage
The Jenkins app is set to reuse existing storage (creates new if none exists). [`pv.yaml`](./pv.yaml) and [`pvc.yaml`](./pvc.yaml) are manifests for this purpose, referencing the respective PVC in [`values.yaml`](./values.yaml). [Reuse of Existing Storage in `kind` (with data persistence)](../../cluster/reuse-storage.md) provides a detailed explanation.
