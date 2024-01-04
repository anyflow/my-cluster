
# 기존 storage 재사용 in `kind` (w/ 데이터 유지)
![storage, pv, pvc binding structure](reuse-storage.png)

## Motivation
storage에 저장된 데이터는 app 또는 cluster의 lifecycle과는 별개로 다룰 필요는 항시 발생하기 마련이다. 예컨데 [Docker Registry](../apps/docker-registry/) app에서 많은 container image를 저장했을 때, (memory 부족 등 어떤 이유에서건) Docker Registry app 또는 cluster 자체를 재기동해야 하는 경우가 있다. 이를 해결하기 위한 구체적 요구사항은 다음이 될 것이다.

1. app이 삭제되더라도 데이터는 삭제되지 않도록
2. 기존 데이터를 신규 app과 cluster에서 사용 가능하도록

[`kind`](https://kind.sigs.k8s.io/)가 사용하는 기본 Storage class (`standard`)인 [`local-path-provisioner`](https://github.com/rancher/local-path-provisioner)는 `hostPath`로의 dynamic provisioning을 위함인데, 이 특성 상 사전에 PVC (Persistent Volume Claim)를 지정하지 않으면 새로운 PV (Persistent Volume)를 생성하기에 2번 요구사항과 상충한다. 또한 이 storage class의 default reclaim policy는 PVC가 삭제될 경우 해당 PV도 함께 삭제하는 `Delete`이므로, 1번 요구사항과도 충돌한다.

## Summary
기존 storage와 PV 간 binding, PV와 PVC 간 binding, 그리고 pod가 binding을 마친 PVC를 사용하도록 설정함으로 기존 storage 재사용이 가능하다.

## 설명
Summary에서 논한 두 가지 binding과 이를 통해 만들어진 PVC 사용 설정에 관한 상세 내용이다.

### 기존 storage와 PV 간 binding

#### 1. `spec.hostPath` 설정
(pod 관점에서의 node에 해당하는) host내 저장 path를 지정한다. 이 path의 prefix는 [`kind-config.yaml`](../kind-config.yaml)의 `nodes.extraMounts.containerPath`와 맞춰야 cluster 외부, 즉 `kind` cluster의 host에서 해당 directory를 조회할 수 있다. [`kind-config.yaml`](../kind-config.yaml)의 `nodes.extraMounts.hostPath`는 외부 관점에서의 해당 directory path를 의미한다.

#### 2. `spec.nodeAffinity` 설정
기존의 storage가 위치한 node가 아닌 타 node에 pod가 생성되는 것을 방지하기 위함으로, `spec.nodeAffinity` 없이 `hostPath`만 설정하면 기존 storage에 위치한 node가 아닌 타 node에 pod가 생성될 수 있어 기존 storage와의 binding에 실패한다.

### PV와 PVC 간 binding

> 자세한 내용은 Kubernetes 공식 가이드인 [Reserving a Persistent Volume](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#reserving-a-persistentvolume)를 참조한다.

다음 세 가지를 설정한다.

1. **`spec.storageClassName: ""`**: `""`를 지정하지 않으면 default인 `standard`가 기본 지정되어 dynamic provisioning이 발생한다. PV, PVC 모두에 설정한다.
2. **`spec.volumeName` 설정**: PVC 설정 항목으로서, binding 대상의 PV name을 지정한다.
3. **`spec.claimRef` 설정**: PV 설정 항목으로서, PVC name과 namespace를 지정한다. 타 PVC가 binding함을 막기 위함이다.

### PVC 사용 설정

마지막으로 위 절차로 만들어진 PVC를 pod에서 사용하도록 설정한다. 아래 예제의 [Docker Registry](../apps/docker-registry/)의 경우 [helm chart value](../apps/docker-registry/values.yaml)의 `persistence.existingClaim` 항목에 해당 PVC name을 지정하는 방법을 사용한다.

## 예제
아래는 위 설명에 따른 [`docker-registry`](../apps/docker-registry/) app에서 사용하는 pv, pvc 설정 예이다.

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: docker-registry
spec:
  storageClassName: "" # To prevent dynamic provisioning
  claimRef:
    name: docker-registry # Set PVC name for reserving
    namespace: cluster # Set PVC namespace for reserving
  persistentVolumeReclaimPolicy: Retain # To prevent Storage Deletion upon PVC Deletion
  accessModes:
    - ReadWriteOnce
  capacity:
    storage: 10Gi
  hostPath:
    path: /var/local-path-provisioner/docker-registry # For binding the PV to storage
    type: DirectoryOrCreate
  nodeAffinity:  # For binding the PV to storage
    required:
      nodeSelectorTerms:
        - matchExpressions:
            - key: kubernetes.io/hostname
              operator: In
              values:
                - my-cluster-worker
```

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: docker-registry
  namespace: cluster
spec:
  storageClassName: "" # To prevent dynamic provisioning
  volumeName: docker-registry # For binding the PVC to the PV
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
```