# Deployment로 MongoDB Replica Set 구성하기

- [Deployment로 MongoDB Replica Set 구성하기](#deployment로-mongodb-replica-set-구성하기)
  - [Description](#description)
  - [본 구조의 문제점](#본-구조의-문제점)
  - [Prerequisite](#prerequisite)
  - [mongodb ReplicaSet 생성](#mongodb-replicaset-생성)

## Description

- mongodb replication cluster를 k8s kind cluster로 설정한다. via `Deployment`
- **본 구조의 문제점**
  - Persistent Volume을 사용하지 않았으므로 **pod가 사라지는 즉시 데이터도 삭제됨**
  - 이를 해결하기 위해서 `Deployment` / `ReplicaSet`이 아닌 **`StatefulSet`** 기반으로 생성을 해야함

## Prerequisite

1. `kind-config.yaml`과 동일 directory 하위로 `./hostroot_in_node/mongo/keyfile` 생성 (`keyfile`은 첨부 참조)
   ```yaml
   # kind-config.yaml

   apiVersion: kind.x-k8s.io/v1alpha4
   kind: Cluster

   nodes:
   - role: control-plane # configuration for control-plane node


   - role: worker # configuration for worker1 node
   extraMounts:
      - hostPath: ./hostroot_in_node
         containerPath: /hostroot
   - role: worker # configuration for worker2 node
   extraMounts:
      - hostPath: ./hostroot_in_node
         containerPath: /hostroot
   - role: worker # configuration for worker3 node
   extraMounts:
      - hostPath: ./hostroot_in_node
         containerPath: /hostroot
   ```
   ```bash
   #keyfile

   5ID8J/YhZarHwW1jBuq05K2yDxhc7dR4Zk5FJyrwg27EluKgkVcJeGlGwlamu83n
   41dqXiKesAsFGqLkrBY0eJpQ7sJqZFee6LeYvbXdTht9ymTu0KO6FNbUYp/+NO5+
   cJTwia8YOtiew7raS4flIsgb455rMV1BUsdM6s1oTp4Mj2ayqVeXppAHSZD5TgYe
   VMhn8iLvuVDyIYyXNQxj2b9XPSsFV4fw+xsq1jdKZE2R7IGpajpLqOVi5qZiqMis
   UpVxaoNuzoTzKExlMSwV58Uzul2eLFbrnuTLXcnSYvBQjXSAMtEpeUGReyF1+CNh
   2CzlL4WvFLwxpsoVF6l4EIdJLTwRkX1guuC0TVHpgmz+Twg551UFh4U2iAK/mQhW
   yDdSmR9aXVJ/Q61imS+4/3pa0Wl/G6NtvWCWuGxQn7j3tv/M9XKM3tkF1qMy5hwC
   zjQWpjDalKzWIioLoe58nx9sLYuhvh18wPFsJvvwf//DqFMozUuFoxx8d2ry4CeA
   LufFaW/BKgrpmuEpIS7D6di6mPGeeMZtLgCMEe0s6XFNS3hz5sCd6IUMsKTvaNbe
   oTSDJ2SqM+0w/hSA1fpryB5Z0SYln1kX6HVRKZLXMjwap69hf+eFyPIPGlCkhqnY
   JmumcLehBeqvw/NLhiqtHo8+HCX+3IqtGhlxeypKFZHA/wJzZnu9DkVL31LI1Btm
   sxJ2bc7tAEzxJ9UUpAbxMGkFGtFdvie1dIvU33dxuKQyHb5iq+9pgf/8Tjx5kxUb
   rb+YFa9YtPcS1ExIbfyWWAr58/VtLnPxaswLOgejxoET/NP/twPjpb/x831g5/9K
   piVaAX8b3vIZCjYY6fvQiMxI0J19QSGQci27a+XM/ejm+sojMnyA7YZXAftG8meR
   rIFQ1IVKjztOmXgqtRyrCFb4kAtlx1LmEUospBNnaVLkJQD9xHuHI9OLSx9tn47S
   1hMdX3zLqA+cx1tS/30bjDyV5L4Q
   ```

2. kind cluster 생성. 명령여 : `kind create cluster --config ./kind-config.yaml`
3. *참고 : pod에서의 `keyfile` 참조 구조* (`kind-config.yaml`의 `extraMounts` 참고)
   ```plantuml
   !theme lightgray
   scale 800 width
   package k8s-kind-cluster {
      package node1 {
         package pod {
            object directory_in_pod1 {
               directory = /hostroot
            }
         }

         object shared_directory1 {
            directory = /hostroot
         }
      }

      package node2 {
         package pod2 {
            object directory_in_pod2 {
               directory = /hostroot
            }
         }

         object shared_directory2 {
            directory = /hostroot
         }
      }

      package node3 {
         package pod3 {
            object directory_in_pod3 {
               directory = /hostroot
            }
         }

         object shared_directory3 {
            directory = /hostroot
         }
      }
   }

   object some_directory_in_localhost {
      directory = ./hostroot_in_node
   }

   directory_in_pod1 --> shared_directory1
   shared_directory1 --> some_directory_in_localhost
   directory_in_pod2 --> shared_directory2
   shared_directory2 --> some_directory_in_localhost
   directory_in_pod3 --> shared_directory3
   shared_directory3 --> some_directory_in_localhost
   ```

## mongodb ReplicaSet 생성

1. 3개의 mongodb instance 생성

   ```bash
   > kubectl apply -f ./deployment-mongo.yaml
   ```

2. 특정 mongodb pod에 접근

   ```bash
   > kubectl exec --stdin --tty <mongodb pod name> -- /bin/bash
   ```

   또는

   ```bash
   > kubectl exec -it <mongodb pod name> -- bash
   ```

3. mongoshell로 해당 mongodb에 접근

   ```bash
   > mongosh --host localhost:27017
   ```

4. mongodb localhost exception 설정

   ```javascript
   > rs.initiate() #initiate replica set
   > use admin # admin db 사용
   > db.createUser({ #admin 생성
      user: "mongo-admin",
      pwd: "mongo-pass",
      roles: [{role: "root", db: "admin"}]
     })
    > exit #localhost exception 빠져나오기(logout)
   ```

5. replica set cluster 구성

   ```bash
   #admin으로 다시 login
   > mongosh --host localhost:27017 -u mongo-admin -p mongo-pass --authenticationDatabase admin
   > rs.add('<other mongodb pod ip #1>:27017') #첫 번째 replica를 cluster에 추가
   > rs.add('<other mongodb pod ip #2>:27017') #두 번째 replica를 cluster에 추가
   > rs.status() # 추가된 두 node의 상태(stateStr)가 정상적 연결 상태인 'SECONDARY'인지 여부 확인

   # 아래는 상기 rs.status() 상태의 결과가 'SECONDARY'가 아닌 'STARTUP' 상태일 경우 수행.
   # 'STARTUP' 상태 원인 : 현재 current node가 pod name으로 hostname이 설정되어 있는데, 타 노드가 pod name으로는 접근할 수 없기 때문
   # 해결책 : hostname으로된 host 값을 ip로 변경
   > cfg = rs.conf() # cfg = rs.config()와 동일
   > cfg.members[0].host = '<current mongodb pod ip>:27017'
   > rs.reconfig(cfg)
   ...

   # 기타 replicaset 관련 명령어
   > rs.status() # 상태 확인
   > rs.isMaster() # 어느 node가 primary인지 확인
   > rs.stepDown() # primary 변경(re-election)
   ```
