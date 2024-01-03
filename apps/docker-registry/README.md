# Docker Registry

## Requirements
- Enable the use of images in MyCluster without dependence on external registries like Docker Hub.
- Allow image pushing from both local and remote sources.
- Ensure data stored in storage remains intact and reusable even if the Cluster or Docker Registry App is removed.
- Minimize or eliminate the complexity of settings and usage due to authentication, etc.

## Image & Helm
- Image: [https://hub.docker.com/_/registry](https://hub.docker.com/_/registry)
- Tag: 2.8.3
- Helm repo description: [https://artifacthub.io/packages/helm/phntom/docker-registry](https://artifacthub.io/packages/helm/phntom/docker-registry)

## Why Docker Registry not Harbor?
- The commonly used container registry app seems to be [`harbor`](https://goharbor.io/).
- However, for the above purposes, `harbor` is a kind of over-engineering. It's unnecessarily complicated and heavy compared to Docker Registry.

## About Using Manual Provisioning for Persistent Volume
### Related manifests
- [`/cluster/storageclass-manual.yaml`](../../cluster/storageclass-manual.yaml): Manual storage class manifest
- [`pv.yaml`](./pv.yaml): Persistent Volume
- [`pvc.yaml`](./pvc.yaml): Persistent Volume Claim

### Purpose
To prevent data deletion even if the app is removed.

### Explanation
The default Storage Class of `kind`, `standard`, uses [local-path-provisioner](https://github.com/rancher/local-path-provisioner), which employs dynamic provisioning. This makes it impossible to manually bind specific PV and PVC (`selector` can't be used in `pvc`), and the default `persistentVolumeReclaimPolicy` of PV is `Delete`, not `Retain`, leading to the deletion of the bound PV and data when PVC is removed.

Therefore, to retain and reuse data even after app deletion, it's necessary to manually handle PV and PVC, leading to the need for manual provisioning. The [related manifests](#Related-manifests) are set up for this purpose.
