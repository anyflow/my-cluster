
# Cluster level manifest

## [`storageclass-manual.yaml`](.storageclass-manual.yaml)

### 목적
app이 삭제되더라도 데이터는 삭제되지 않도록 하기 위함

### 설명
`kind`의 기본 Storage Class인 `standard`는 [local-path-provisioner](https://github.com/rancher/local-path-provisioner)를 사용하는데, 이는 dynamic provisioning을 사용하기에 수작업으로 특정 PV와 PVC를 binding할 수가 없고(`pvc`에서 `selector` 사용 불가능), PV의 기본 `persistentVolumeReclaimPolicy`가 `Retain`이 아닌 `Delete`이기에 PVC가 삭제될 때 binding된 PV 및 data가 삭제된다.

따라서, app이 삭제되더라도 data를 유지하고 재사용하기 위해서는 직접 PV, PVC를 처리해야 하며 결국 manual provisioning을 해야 한다. [관련 manifest](#관련-manifest)는 이를 위한 설정이다.
