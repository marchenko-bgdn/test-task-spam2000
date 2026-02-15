#!/usr/bin/env bash
set -euo pipefail

PROFILE="${MINIKUBE_PROFILE:-minikube}"
CPUS="${MINIKUBE_CPUS:-4}"
MEMORY="${MINIKUBE_MEMORY:-7680}"
DISK="${MINIKUBE_DISK:-30g}"

ARGOCD_NS="argocd"
ARGO_HELM_REPO="https://argoproj.github.io/argo-helm"
ARGO_CHART="argo/argo-cd"
ARGO_CHART_VERSION="${ARGOCD_CHART_VERSION:-9.4.1}"

function info() { echo -e "\n==> $*"; }

function require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1"; exit 1; }
}

function wait_deploy() {
  local ns="$1"
  local deploy="$2"
  kubectl -n "$ns" rollout status deploy/"$deploy" --timeout=10m
}

info "Checking prerequisites"
require_cmd minikube
require_cmd kubectl
require_cmd helm
require_cmd git

info "Starting minikube profile=${PROFILE} (cpus=${CPUS}, memory=${MEMORY}MB, disk=${DISK})"
minikube start -p "${PROFILE}" --driver=docker --cpus="${CPUS}" --memory="${MEMORY}" --disk-size="${DISK}"

info "Enabling ingress addon"
minikube -p "${PROFILE}" addons enable ingress

info "Applying namespaces"
kubectl apply -f clusters/minikube/namespaces.yaml

info "Installing Argo CD via Helm (bootstrap)"
helm repo add argo "${ARGO_HELM_REPO}" >/dev/null
helm repo update >/dev/null

helm upgrade --install argocd "${ARGO_CHART}" \
  --namespace "${ARGOCD_NS}" --create-namespace \
  --version "${ARGO_CHART_VERSION}" \
  --set server.service.type=ClusterIP \
  --wait --timeout 10m

info "Waiting Argo CD server to be ready"
wait_deploy "${ARGOCD_NS}" argocd-server

info "Applying Argo CD root app (GitOps begins here)"
kubectl apply -n "${ARGOCD_NS}" -f clusters/minikube/root-app.yaml

info "Done."
info "Argo CD will now sync applications from clusters/minikube/apps"
info "Use: make argocd  /  make grafana"