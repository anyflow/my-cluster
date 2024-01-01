
# Docker Registry


## 목적

- dockerhub에 등록하지 않은 container image를 사용 가능하도록
- Kubernetes 내부 뿐 아니라 internet을 통해서도 container registry에 image를 push 가능하도록

## Why Docker Registry not Harbor?

일반적으로 많이 사용하는 container registry 앱은 [`harbor`](https://goharbor.io/)인 듯 하나, MyCluster 대비 불필요한 기능이 많이 포함됨. container registry의 가장 기본적인 기능만이 필요한 상황에서 `harbor`는 일종의 over-engineering.

##
https://artifacthub.io/packages/helm/twuni/docker-registry

harbor를 안쓰고 docker-registry를 쓴 이유. harbor가 너무 무겁기 때문에
