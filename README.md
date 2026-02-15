# DevOps Test Task

This repository bootstraps a local GitOps Kubernetes environment using **Minikube** and **Argo CD**, and deploys a monitoring stack (**VictoriaMetrics + Grafana**) and a demo application (**spam2000**) that exposes Prometheus metrics.

---

## Stack

- **Kubernetes (local):** Minikube
- **GitOps:** Argo CD (Helm install) + Root Application
- **Monitoring:** VictoriaMetrics stack (vmstack) + Grafana
- **App:** spam2000 (metrics generator)

---

## Prerequisites

Installed locally:

- Docker Desktop
- `kubectl`
- `helm`
- `minikube`
- `make`

You can install tools via Homebrew:

```bash
brew install kubectl helm minikube
```

## Quick start

Start everything:

```bash
make up
```

`make up` does the following:
1. Starts Minikube profile `minikube`
2. Creates namespaces (`argocd`, `monitoring`, `apps`)
3. Installs Argo CD using Helm
4. Applies root app (`clusters/minikube/root-app.yaml`)
5. Waits for Argo CD apps to become `Synced` and `Healthy`
6. Starts local port-forwards for Argo CD and Grafana

Stop and clean up:

```bash
make down
```

This stops background port-forwards and deletes the Minikube profile.

## Access

After `make up`:
- Argo CD: `http://127.0.0.1:8080`
- Grafana: `http://127.0.0.1:3000`

Default credentials:
- Argo CD: user `admin`, password is printed by `make up`
- Grafana: user `admin`, password is printed by `make up`

## Optional configuration

You can override defaults when starting:

```bash
MINIKUBE_PROFILE=minikube MINIKUBE_CPUS=4 MINIKUBE_MEMORY=7680 MINIKUBE_DISK=30g \
ARGOCD_PORT=8080 GRAFANA_PORT=3000 make up
```

If ports `8080` or `3000` are busy, use different values (for example `ARGOCD_PORT=18080 GRAFANA_PORT=13000 make up`).
