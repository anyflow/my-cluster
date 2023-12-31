- [Description](#description)
- [사전 준비](#사전-준비)
- [설치](#설치)
  - [k8s 클러스터 생성](#k8s-클러스터-생성)
  - [mongoDB 인스턴스 생성](#mongodb-인스턴스-생성)
  - [MongoDB Replica Set 설정](#mongodb-replica-set-설정)
- [테스트](#테스트)
  - [1. mongoDB Replica Set 정상 동작 확인](#1-mongodb-replica-set-정상-동작-확인)
  - [2. StatefulSet 전체를 삭제하고(pod 포함) 다시 생성해도 기존 데이터가 살아있는지 확인](#2-statefulset-전체를-삭제하고pod-포함-다시-생성해도-기존-데이터가-살아있는지-확인)
- [생각해보기](#생각해보기)
- [References](#references)
- [Appendix #1 : `statefule-mongo-kind-config.yaml`](#appendix-1--statefule-mongo-kind-configyaml)
- [Appendix #2 : `statefule-mongo.yaml`](#appendix-2--statefule-mongoyaml)

# Description

- StatefulSet을 사용한 MongoDB Replica Set 설치, 테스트 방법이다.

# 사전 준비

- 동적 생성된 volume 저장용 directory, mongoDB 공유 `keyfile` 저장용 directory 생성

  ```bash
  > mkdir ./pvc ./hostroot_in_node
  ```

- mongoDB용 `keyfile` 생성 및 권한 설정

  ```bash
  > openssl rand -base64 741 > ./hostroot_in_node/mongo/keyfile
  ...
  > chmod 400 ./hostroot_in_node/mongo/keyfile
  ```

# 설치
## k8s 클러스터 생성

- k8s 클러스터 생성

  ```bash
  > kind create cluster --config ./statefulset-mongo-kind-config.yaml
  ```

## mongoDB 인스턴스 생성

- StatefulSet 기반으로 mongoDB 배포

  ```bash
  > kubectl apply -f ./statefulset-mongo.yaml
  ```

  > **StatefulSet manifest 생성 시 확인 사항**
  >
  > - **Headless Service 생성**
  >   - StatefulSet은 Load Balancer가 무의미하므로 LB 동작 X.
  > - **Service에 selector 설정**
  >   - selector가 Pod를 가리키도록 설정해야 각 Pod가 DNS에 등록됨
  > - **`statefulset-mongo.yaml`에서의 해당 설정**
  >   ```yaml
  >   apiVersion: v1
  >   kind: Service
  >   ...
  >   spec:
  >     clusterIP: None     # headless service via None ClusterIP : No load balancer, But DNS
  >     selector:
  >       app: mongodb      # To be looked up by DNS, the selector should be matched with the pod's.
  >   ...
  >   ```

- 정상 배포 확인 (w/ 성공 output)

  ```bash
  > kubectl get all
  ...
  NAME          READY   STATUS              RESTARTS   AGE
  pod/mongo-0   1/1     Running   0          6m3s
  pod/mongo-1   1/1     Running   0          5m21s
  pod/mongo-2   1/1     Running   0          4m40s

  NAME                      TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)     AGE
  service/kubernetes        ClusterIP   10.96.0.1    <none>        443/TCP     11m
  service/mongodb-service   ClusterIP   None         <none>        27017/TCP   6m3s

  NAME                     READY   AGE
  statefulset.apps/mongo   3/3     6m3s

  > kubectl get pv,pvc
  ...
  NAME                                                        CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                                           STORAGECLASS   REASON   AGE
  persistentvolume/pvc-0acb895f-5c83-4344-a465-2ffc30751282   1Gi        RWO            Delete           Bound    default/mongo-persistent-volume-claim-mongo-2   standard                10m
  persistentvolume/pvc-73ddbf20-76ea-4d64-b96d-4e6151f04cdd   1Gi        RWO            Delete           Bound    default/mongo-persistent-volume-claim-mongo-1   standard                11m
  persistentvolume/pvc-77266513-3c08-494e-ad57-731e7c42d823   1Gi        RWO            Delete           Bound    default/mongo-persistent-volume-claim-mongo-0   standard                11m

  NAME                                                          STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
  persistentvolumeclaim/mongo-persistent-volume-claim-mongo-0   Bound    pvc-77266513-3c08-494e-ad57-731e7c42d823   1Gi        RWO            standard       11m
  persistentvolumeclaim/mongo-persistent-volume-claim-mongo-1   Bound    pvc-73ddbf20-76ea-4d64-b96d-4e6151f04cdd   1Gi        RWO            standard       11m
  persistentvolumeclaim/mongo-persistent-volume-claim-mongo-2   Bound    pvc-0acb895f-5c83-4344-a465-2ffc30751282   1Gi        RWO            standard       10m
  ```

- DNS에 mongodb-service 및 개별 pod가 정상 등록되었는지 확인

  ```bash
  > kubectl apply -f /k8s.io/examples/admin/dns/dnsutils.yaml # cluster내에서 nslookup 실행을 위한 dnsutils pod 설치
  ...
  pod/dnsutils created

  > kubectl exec -i -t dnsutils -- nslookup mongodb-service # mongodb-service가 nslookup 되는지 확인
  ...
  Server:         10.96.0.10
  Address:        10.96.0.10#53
  Name:   mongodb-service.default.svc.cluster.local
  Address: 10.244.2.3
  Name:   mongodb-service.default.svc.cluster.local
  Address: 10.244.1.3
  Name:   mongodb-service.default.svc.cluster.local
  Address: 10.244.3.3

   # 개별 pod가 nslookup 되는지 확인
  > kubectl exec -i -t dnsutils -- nslookup mongo-0.mongodb-service # mongo-1, mongo-2에 대해서도 각기 수행
  ...
  Server:         10.96.0.10
  Address:        10.96.0.10#53

  Name:   mongo-0.mongodb-service.default.svc.cluster.local
  Address: 10.244.2.3
  ```
## MongoDB Replica Set 설정

  ```bash
  > kubectl exec -it mongo-0 -- bash # mongo-0의 shell에 로그인
  ...
  > mongosh # mongo shell에 로그인
  ...
  # mongoDB Replica Set 구성을 위해 각 node 연결 (위에서 확인한 Domain을 hostname으로 사용 중)
  > rs.initiate({ _id: "anyflow-replset", version: 1, members: [
  ... {_id: 0, host: "mongo-0.mongodb-service:27017" },
  ... { _id: 1, host : "mongo-1.mongodb-service:27017" },
  ... {_id: 2, host: "mongo-2.mongodb-service:27017" }] });
  ...
  # 정상적으로 MongoDB Replica Set이 생성되었는지 확인
  > rs.status()
  ...
  {
    set: 'anyflow-replset',
    ...
    members: [
        {
            _id: 0,
            name: 'mongo-0.mongodb-service:27017',
            ...
            stateStr: 'PRIMARY',
            ...
        },
        {
            _id: 1,
            name: 'mongo-1.mongodb-service:27017',
            ...
            stateStr: 'SECONDARY', # 정상 연결이 안되면 STARTUP 등 타 값이 나타남
            ...
        },
        {
            _id: 2,
            name: 'mongo-2.mongodb-service:27017',
            ...
            stateStr: 'SECONDARY', # 정상 연결이 안되면 STARTUP 등 타 값이 나타남
            ...
        }
    ],
    ok: 1,
    ...
  }

  # admin 계정 생성 mongoDB의 Localhost Exception 모드 제거
  > db.getSiblingDB('admin').createUser({ user:'mongo-admin', pwd:'mongo-pass', roles:[{role:'root',db:'admin'}]});
  ...

  > exit
  ```

# 테스트

## mongoDB Replica Set 정상 동작 확인

: primary에서 데이터를 넣고, secondary에서 해당 데이터가 존재하는지 확인

- primary에서 데이터 삽입

  ```bash
  > kubectl exec -it mongo-0 -- bash # primary인 mongo pod에 접근
  ...
  > mongosh -u mongo-admin -p mongo-pass  # mongo shell에 로그인(w/ admin 계정)
  ...
  > db.testcoll.insertOne({a:1}); # 데이터 insert
  ...
  > db.testcall.find() # 정상 insert 결과 확인
  ...
  [
    { _id: ObjectId("62763e88695fad1b80b8bd4f"), a: 1 }
  ]
  ```

- secondary에서 삽입한 데이터 확인

  ```bash
  > kubectl exec -it mongo-1 -- bash # secondary인 mongo pod에 접근
  ...
  > mongosh -u mongo-admin -p mongo-pass  # mongo shell에 로그인(w/ admin 계정)
  ...
  > db.getMongo().setReadPref('secondary') # secondary에서 read 가능하도록 설정
  ...
  > db.testcall.find() # 기존에 삽입된 데이터 확인
  ...
  [
    { _id: ObjectId("62763e88695fad1b80b8bd4f"), a: 1 }
  ]
  ```

## StatefulSet 전체를 삭제하고(pod 포함) 다시 생성해도 기존 데이터가 살아있는지 확인

```bash
> kubectl delete -f ./statefulset-mongo.yaml  # 전체 삭제
...
> kubectl apply -f ./statefulset-mongo.yaml  # 재생성
...
> kubectl exec -it mongo-1 -- bash # mongo pod에 접근
...
> mongosh -u mongo-admin -p mongo-pass  # mongo shell에 로그인(w/ 기존 admin 계정)
...
> db.getMongo().setReadPref('secondary') # secondary에서 read 가능하도록 설정
...
> db.testcall.find() # 기존에 삽입된 데이터 확인
...
[
  { _id: ObjectId("62763e88695fad1b80b8bd4f"), a: 1 }
]
```

  - 재생성 시 PV에 데이터가 남아 있기에, 기존의 Replica 설정 및 계정, 데이터 생성 작업이 불필요
# 생각해보기

- **재생성 시 어떤 로직으로 pod가 기존 PVC에 연동이 되는지?**
  - StatefulSet을 삭제했다고 해서 PV, PVC가 삭제되는 것이 아님. 단순히 pod의 삭제임
  - PVC name은 `VolumeClaimTemplates.meta.name`에 pod의 `meta.name`이 postfix로 붙음. e.g. `mongo-persistent-volume-claim-mongo-0` 이를 통해 자연스럽게 기존 PVC에 연동될 수 있겠네...
- **PV는 언제 삭제되는지?**
  - static provisioning이면 RECLAIM POLICY가 `Retain`이고, dynamic provisioning이면 `Delete`임.
  - 본 예제의 경우 dynamic provisioning이며, 해당 PVC가 삭제될 때 자동으로 함께 삭제됨.


# References

- [Running MongoDB on Kubernetes with StatefulSets](<https://kubernetes.io/blog/2017/01/running-mongodb-on-kubernetes-with-statefulsets/>)
- [Mongodb Replica Set on Kubernetes](<https://maruftuhin.com/blog/mongodb-replica-set-on-kubernetes/>)

## Appendix #1 : `statefule-mongo-kind-config.yaml`

```yaml
apiVersion: kind.x-k8s.io/v1alpha4
kind: Cluster

nodes:
- role: control-plane # configuration for control-plane node

- role: worker # configuration for worker1 node
  extraMounts:
    - hostPath: ./hostroot_in_node
      containerPath: /hostroot
    - hostPath: ./pvc
      containerPath: /var/local-path-provisioner
- role: worker # configuration for worker2 node
  extraMounts:
    - hostPath: ./hostroot_in_node
      containerPath: /hostroot
    - hostPath: ./pvc
      containerPath: /var/local-path-provisioner
- role: worker # configuration for worker3 node
  extraMounts:
    - hostPath: ./hostroot_in_node
      containerPath: /hostroot
    - hostPath: ./pvc
      containerPath: /var/local-path-provisioner
```

## Appendix #2 : `statefule-mongo.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: mongodb-service
  labels:
    name: mongo
spec:
  ports:
  - port: 27017
    targetPort: 27017
  clusterIP: None     # headless service via None ClusterIP : No load balancer, But DNS
  selector:
    app: mongodb      # To be looked up by DNS, the selector should be matched with the pod's.
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mongo
spec:
  serviceName: mongodb-service
  selector:
    matchLabels:
      app: mongodb
  replicas: 3
  template:
    metadata:
      labels:
        app: mongodb
    spec:
      containers:
      - name: mongo
        image: mongo:5.0.7
        args:
        - '--bind_ip'
        - '0.0.0.0'
        - '--replSet'
        - 'anyflow-replset'
        - '--auth'
        - '--clusterAuthMode'
        - 'keyFile'
        - '--keyFile'
        - '/hostroot/mongo/keyfile'
        - "--setParameter"
        - "authenticationMechanisms=SCRAM-SHA-1"
        resources:
          limits:
            memory: '128Mi'
            cpu: '500m'
        ports:
        - containerPort: 27017
        volumeMounts:
        - name: hostroot
          mountPath: /hostroot
        - name: mongo-persistent-volume-claim
          mountPath: /data/db
      volumes:
      - name: hostroot
        hostPath:
          path: /hostroot
  volumeClaimTemplates:
  - metadata:
      name: mongo-persistent-volume-claim
    spec:
      storageClassName: standard # standard는 kind에 기본적으로 딸려오는 provisioner로 local-path-provisioner를 사용
      accessModes:
        - ReadWriteOnce
      resources:
        requests:
          storage: 1Gi
```