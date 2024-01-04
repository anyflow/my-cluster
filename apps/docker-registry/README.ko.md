
# App: Docker Registry

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
- 일반적으로 많이 사용하는 container registry 앱은 [Harbor](https://goharbor.io/)인 듯.
- 그러나 Harbor는 상기 목적 상 일종의 over-engineering으로, Docker Registry에 비해 불필요하게 사용법이 복잡하고 무거움.

## 기존 storage 재사용에 관하여
Docker Registry app은 기존 storage 재사용이 가능하다. [`pv.yaml`](./pv.yaml), [`pvc.yaml`](./pvc.yaml)은 이를 위한 manifest로, [`value.yaml`](./values.yaml)에서 해당 pvc를 참조한다. [기존 storage 재사용 in `kind` (w/ 데이터 유지)](../../cluster/reuse-storage.kr.md)는 이에 대한 상세 설명이다.