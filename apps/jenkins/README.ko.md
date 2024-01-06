# App: Jenkins

## 중점 고려 사항
- **기존 사용자 설정(plugins, credential 등) 및 job 재사용**: 설치 시마다 이들을 재설정하는 번거로움을 피하기 위함이다. 이는 하기 [기존 storage 재사용에 관하여](#기존-storage-재사용에-관하여)를 통해 달성한다.

## 설정
- **사용된 Helm chart**
  - https://github.com/jenkinsci/helm-charts/blob/main/charts/jenkins/README.md
- **접근 주소**
  - `.env`에 정의된 `DOMAIN_JENKINS` 값
- **Data 저장 위치**
  - `/nodes/worker0/var/local-path-provisioner/jenkins`
- **관련 명령 in [Makefile](../../Makefile)**
  - 생성: `make jenkins-c`
  - 삭제: `make jenkins-d`

## 기존 storage 재사용에 관하여
Jenkins app은 기존 storage 재사용을 하도록 설정되었다(없으면 신규 생성). [`pv.yaml`](./pv.yaml), [`pvc.yaml`](./pvc.yaml)은 이를 위한 manifest로, [`value.yaml`](./values.yaml)에서 해당 pvc를 참조한다. [기존 storage 재사용 in `kind` (w/ 데이터 유지)](../../cluster/reuse-storage.kr.md)는 이에 대한 상세 설명이다.