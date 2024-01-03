
# Docker Registry

## Requirements
- Docker Hub 등 외부 registry에 대한 의존 없이도 image를 MyCluster에서 사용 가능하도록
- Local 뿐 아니라 remote에서도 image push 가능하도록
- Cluster 또는 Docker Registry App이 제거되더라도 storage에 저장된 data는 유지되고, 재사용 가능하도록
- 인증 등으로 인한 설정, 사용법 복잡도를 제거 또는 최소화가 되도록

## Image & Helm
- Image: https://hub.docker.com/_/registry
- Tag: 2.8.3
- Helm repo description: https://artifacthub.io/packages/helm/phntom/docker-registry
## Why Docker Registry not Harbor?
- 일반적으로 많이 사용하는 container registry 앱은 [`harbor`](https://goharbor.io/)인 듯.
- 하지만 `harbor`는 상기 목적 상 일종의 over-engineering. Docker Registry에 비해 불필요하게 사용법이 복잡하고 무거움.

## Persistent Volume의 Manual Provisioning 사용에 관하여
### 관련 manifest:
- [`/cluster/storageclass-manual.yaml`](../../cluster/storageclass-manual.yaml): manual storageclass manifest
- [`pv.yaml`](./pv.yaml): Persistent Volume
- [`pvc.yaml`](./pvc.yaml): Persistent Volume Claim

### 목적
app이 삭제되더라도 데이터는 삭제되지 않도록 하기 위함

### 설명
`kind`의 기본 Storage Class인 `standard`는 [local-path-provisioner](https://github.com/rancher/local-path-provisioner)를 사용하는데, 이는 dynamic provisioning을 사용하기에 수작업으로 특정 PV와 PVC를 binding할 수가 없고(`pvc`에서 `selector` 사용 불가능), PV의 기본 `persistentVolumeReclaimPolicy`가 `Retain`이 아닌 `Delete`이기에 PVC가 삭제될 때 binding된 PV 및 data가 삭제된다.

따라서, app이 삭제되더라도 data를 유지하고 재사용하기 위해서는 직접 PV, PVC를 처리해야 하며 결국 manual provisioning을 해야 한다. [관련 manifest](#관련-manifest)는 이를 위한 설정이다.
