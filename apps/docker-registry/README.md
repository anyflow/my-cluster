
# Docker Registry


## 목적

- dockerhub에 등록하지 않은 container image를 사용 가능하도록
- Kubernetes 내부 뿐 아니라 internet을 통해서도 container registry에 image를 push 가능하도록



## 설계 상 결정 사항

### Lightweight
일반적으로 많이 사용하는 container registry 앱은 [`harbor`](https://goharbor.io/)인 듯 하나, MyCluster 성격 상 단순하고 가벼운 서비스를 선택함

https://artifacthub.io/packages/helm/twuni/docker-registry

harbor를 안쓰고 docker-registry를 쓴 이유. harbor가 너무 무겁기 때문에
