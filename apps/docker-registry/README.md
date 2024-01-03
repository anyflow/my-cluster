# App: Docker Registry

## Requirements
- Ability to use images in MyCluster without relying on external registries like Docker Hub.
- Enable image push capabilities both locally and remotely.
- Ensure that data stored in storage remains intact and reusable, even if the Cluster or Docker Registry App is removed.
- Minimize or eliminate complexity in configuration and usage due to authentication.

## Image & Helm
- Image: [https://hub.docker.com/_/registry](https://hub.docker.com/_/registry)
- Tag: 2.8.3
- Helm repo description: [https://artifacthub.io/packages/helm/phntom/docker-registry](https://artifacthub.io/packages/helm/phntom/docker-registry)

## Why Docker Registry not Harbor?
- The commonly used container registry app seems to be [Harbor](https://goharbor.io/).
- However, for the purposes mentioned above, Harbor appears to be a kind of over-engineering. Compared to Docker Registry, it is unnecessarily complex and heavy in its usage.

## About Manual Volume Provisioning
The Docker Registry app uses manual volume provisioning. [pv.yaml](./pv.yaml) and [pvc.yaml](./pvc.yaml) are manifests for this purpose, and [value.yaml]() refers to the respective pvc. [Manual volume provisioning](../../cluster/manual-volume-provisioning.md) provides detailed explanations about this.
