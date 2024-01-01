# My Cluster (DRAFT)
This project aims to 'quickly' set up and tear down a Kubernetes and various apps in the cluster within a single host. The primary purpose is to acquire knowledge about their usage and to conduct tests.

## Objectives
- **Enable installation/deletion of apps, including Kubernetes itself, with a 'single command'**
  - The goal is to restart from the initial setup at any time, ensuring that the installation/deletion process itself doesn't become a bottleneck in understanding the apps.
- **Make it operable in a single host**
  - Essentially, to function as a home server/cluster. Naturally, this includes exposure to the internet.

## Test Results
Operating on a MacBook Pro from 2011 (w/ 16G Memory) under Ubuntu Linux (Refer to the [My Cluster & its assets](https://www.anyflow.net) section for more information).

## Prerequisites
- **`docker`**: Being based on Kubernetes, a container runtime is naturally required. `podman` might also be feasible as it is supported by the below-mentioned `kind`, though it hasn't been tested.
- **`kind`**: A runtime that supports Kubernetes on a single host based on containers. Installation guides for various OS are well documented in the [official kind guide](https://kind.sigs.k8s.io/docs/user/quick-start/).
- **`kubectl`**: The basic command module for Kubernetes. This also has installation guides for various OS in the `kubectl` section of the [official Kubernetes guide](https://kubernetes.io/docs/tasks/tools/).
- **Wildcard Certificate**: Used by `default-gateway`, the primary Gateway of MyCluster, for exposing apps over TLS. The method for linking domains for each app is explained in the [1. Setting up `.env`](#1-setting-up-env) section. The files should be placed in the PEM format as follows:
  - **Fullchain Certificate**: `/cert/fullchain.pem`
  - **Private Key**: `/cert/privkey.pem`

## Usage
All commands include the creation, deletion, and restart of Kubernetes itself, apps, and detailed settings using a Makefile. The naming convention for Makefile rules is `{app name}-c` for creation, `{app name}-d` for deletion, and `{app name}-r` for restart. Here's an example with Prometheus:
- Create: `make prometheus-c`
- Delete: `make prometheus-d`
- Restart: `make prometheus-r`

For specialized aspects of each app, refer to the `README.md` in each app directory in [`/apps`](./apps) directory.

## Getting Started

### 1. Setting up `.env`
Create a `.env` file in the root directory and enter the domain values for each app as shown below. The `...anyflow.net` shown here is an example, and you should input the actual domain name you intend to use(refer to [`sample.env`](sample.env)).

```sh
DOMAIN_ARGOCD=argocd.anyflow.net
DOMAIN_DOCKER_REGISTRY=docker-registry.anyflow.net
...
```

### 2. Create a cluster and set cluster-level configuration
The specific content and procedures for installing/configuring Kubernetes and cluster levels are as follows. For each app, refer to the above usage instructions and install separately as needed.

```bash
# Clone the project
$ git clone https://github.com/anyflow/my-cluster.git
...
# Change current working directory
$ cd my-cluster
...
# Create Kubernetes cluster
$ make cluster-c
...
# Install Load Balancer (used by Kubernetes API)
$ make metallb-c
...
# Add helm repositories for apps
$ make helm_repo-c
...
# Install istio
$ make istio-c
...
# Configure cluster level services. e.g. namspace, metallb, manual storageclass, gateway (, ingress)
$ make config-c
```

## File/Directory Description
```sh
root
├── cluster           # Kubernetes manifests in cluster level
├── apps              # app collection
│  ├── prometheus     # files for app - prometheus
│  ├── ...
├── nodes             # Kubernetes worker node files (ignored in git)
│  ├── worker0        # worker node 0
│  ├── worker1        # worker node 1
│  └── worker2        # worker node 2
├── .env              # Environment Variables used in the Makefile (git ignored)
├── kind-config.yaml  # kind config
├── Makefile          # Makefile rules
├── README.md         # this file
├── .gitignore        # git ignore file
└── sample.env        # .env sample file
```

## Design Decisions

### Using `kind`
Instead of Minikube, [`kind`](https://kind.sigs.k8s.io/) is used, as when this project was initially created, Minikube did not support multi-node setups, and Kubernetes nodes are emulated as containers, making it **lightweight**. This is especially relevant for Kubernetes development. For reference, the first option for operating Kubernetes in a local environment in the [Kubernetes Official Documentation](https://kubernetes.io/docs/tasks/tools/) is `kind`, not Minikube.

### Using Only Two Namespaces: `cluster` and `istio-system`
Other namespaces are not used for convenience. `istio-system` is specifically chosen because using `istio` and its eco family in other namespaces often requires extensive trial and error.

### Using `Kubernetes Gateway API` Instead of `ingress`
The `Kubernetes Gateway API` is a new Kubernetes API that replaces `ingress`, used by default to expose Kubernetes Services externally. This project includes configurations for `ingress`, but most of these are commented out and generally turned off.

### Three Worker Nodes
Considering it operates locally, using three worker nodes is unnecessary. However, they are set to three for testing sharding and replication in systems like `Elasticsearch` and `MongoDB`. If deemed unnecessary, you can configure it to just one node in the `kind-config.yaml` file.

## Supported App List
Below is a list of supported (✅) or planned to be supported (🚧) apps. For more details, refer to the `README.md` in the respective app directory.

- 🚧 `docker-registry`
- 🚧 `jaeger`
- 🚧 `prmetheus`
- 🚧 `grafana`
- 🚧 `elasticsearch`
- 🚧 `fluentbit`
- 🚧 `kibana`
- 🚧 `argocd`
- 🚧 `jenkins`
- 🚧 `wbitt/network-multitool`
- 🚧 `kafka`
- 🚧 `kafkaui`