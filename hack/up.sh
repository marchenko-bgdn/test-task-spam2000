#!/usr/bin/env bash
set -euo pipefail

PROFILE="${MINIKUBE_PROFILE:-minikube}"
CPUS="${MINIKUBE_CPUS:-4}"
MEMORY="${MINIKUBE_MEMORY:-7680}"
DISK="${MINIKUBE_DISK:-30g}"

ARGOCD_NS="argocd"
MON_NS="monitoring"

# UI ports
ARGOCD_PORT="${ARGOCD_PORT:-8080}"
GRAFANA_PORT="${GRAFANA_PORT:-3000}"

# Port-forward pids and logs
PF_DIR="${PF_DIR:-.portforwards}"

ARGO_HELM_REPO="https://argoproj.github.io/argo-helm"
ARGO_CHART="argo/argo-cd"
ARGO_CHART_VERSION="${ARGOCD_CHART_VERSION:-9.4.1}"


GRAFANA_SVC="${GRAFANA_SVC:-vmstack-grafana}"

info() { echo -e "\n==> $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

port_free() {
  local port="$1"
  ! lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
}

pid_alive() {
  local pid="$1"
  [[ -n "${pid}" ]] && kill -0 "${pid}" >/dev/null 2>&1
}

start_port_forward() {
  local name="$1"     # argocd|grafana
  local ns="$2"
  local resource="$3" # svc/xxx
  local mapping="$4"  # local:remote

  mkdir -p "${PF_DIR}"
  local pidfile="${PF_DIR}/${name}.pid"
  local logfile="${PF_DIR}/${name}.log"

  if [[ -f "${pidfile}" ]]; then
    local oldpid
    oldpid="$(cat "${pidfile}" || true)"
    if pid_alive "${oldpid}"; then
      info "Port-forward '${name}' already running (pid ${oldpid})"
      return 0
    fi
    rm -f "${pidfile}"
  fi

  info "Starting port-forward '${name}': ${ns} ${resource} ${mapping}"
  nohup kubectl -n "${ns}" port-forward --address 127.0.0.1 "${resource}" "${mapping}" \
    >"${logfile}" 2>&1 &

  echo $! > "${pidfile}"
  sleep 1

  local newpid
  newpid="$(cat "${pidfile}")"
  pid_alive "${newpid}" || die "Port-forward '${name}' failed. See ${logfile}"
}

wait_deploy() {
  local ns="$1"; local deploy="$2"
  kubectl -n "$ns" rollout status deploy/"$deploy" --timeout=10m
}

wait_svc_exists() {
  local ns="$1"; local svc="$2"; local timeout="${3:-300}"
  info "Waiting for service ${ns}/${svc} to exist..."
  local start; start="$(date +%s)"
  while true; do
    if kubectl -n "$ns" get svc "$svc" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
    local now; now="$(date +%s)"
    (( now - start > timeout )) && return 1
  done
}

wait_secret_exists() {
  local ns="$1"; local secret="$2"; local timeout="${3:-300}"
  info "Waiting for secret ${ns}/${secret} to exist..."
  local start; start="$(date +%s)"
  while true; do
    if kubectl -n "$ns" get secret "$secret" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
    local now; now="$(date +%s)"
    (( now - start > timeout )) && return 1
  done
}

wait_argocd_app() {
  local app="$1"
  local timeout="${2:-600}"

  info "Waiting for ArgoCD app '${app}' to be Synced + Healthy (timeout ${timeout}s)..."
  local start; start="$(date +%s)"

  while true; do
    if kubectl -n "${ARGOCD_NS}" get application "${app}" >/dev/null 2>&1; then
      local sync health
      sync="$(kubectl -n "${ARGOCD_NS}" get application "${app}" -o jsonpath='{.status.sync.status}' 2>/dev/null || true)"
      health="$(kubectl -n "${ARGOCD_NS}" get application "${app}" -o jsonpath='{.status.health.status}' 2>/dev/null || true)"
      if [[ "${sync}" == "Synced" && "${health}" == "Healthy" ]]; then
        info "ArgoCD app '${app}' is Synced + Healthy"
        return 0
      fi
    fi

    sleep 2
    local now; now="$(date +%s)"
    if (( now - start > timeout )); then
      echo "Timeout waiting for app '${app}'. Current:"
      kubectl -n "${ARGOCD_NS}" get application "${app}" -o wide || true
      return 1
    fi
  done
}

get_argocd_password() {
  kubectl -n "${ARGOCD_NS}" get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || true
}

get_grafana_password() {
  local secret pw
  secret="$(kubectl -n "${MON_NS}" get secret -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  [[ -n "${secret}" ]] || return 1

  pw="$(kubectl -n "${MON_NS}" get secret "${secret}" -o jsonpath="{.data['admin-password']}" 2>/dev/null | base64 -d || true)"
  [[ -n "${pw}" ]] || return 1
  echo "${pw}"
}

info "Checking prerequisites"
require_cmd minikube
require_cmd kubectl
require_cmd helm

port_free "${ARGOCD_PORT}" || die "Port ${ARGOCD_PORT} is busy. Free it or run: ARGOCD_PORT=18080 make up"
port_free "${GRAFANA_PORT}" || die "Port ${GRAFANA_PORT} is busy. Free it or run: GRAFANA_PORT=13000 make up"

info "Starting minikube profile=${PROFILE} (cpus=${CPUS}, memory=${MEMORY}MB, disk=${DISK})"
minikube start -p "${PROFILE}" --driver=docker --cpus="${CPUS}" --memory="${MEMORY}" --disk-size="${DISK}"

info "Enabling ingress addon"
minikube -p "${PROFILE}" addons enable ingress >/dev/null || true

info "Applying namespaces"
kubectl apply -f clusters/minikube/namespaces.yaml

info "Installing Argo CD via Helm (bootstrap)"
helm repo add argo "${ARGO_HELM_REPO}" >/dev/null 2>&1 || true
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

# Wait for core apps
wait_argocd_app "root" 600
wait_argocd_app "monitoring" 900
wait_argocd_app "dashboards" 600
wait_argocd_app "spam2000" 600

# Start port-forwards
start_port_forward "argocd" "${ARGOCD_NS}" "svc/argocd-server" "${ARGOCD_PORT}:443"

# Grafana service is stable in your setup
wait_svc_exists "${MON_NS}" "${GRAFANA_SVC}" 600
start_port_forward "grafana" "${MON_NS}" "svc/${GRAFANA_SVC}" "${GRAFANA_PORT}:80"

# Read credentials
ARGO_PWD="$(get_argocd_password)"

info "Resolving Grafana admin password from Secret"
GRAF_PWD=""
for _ in {1..300}; do
  if GRAF_PWD="$(get_grafana_password 2>/dev/null)"; then
    break
  fi
  sleep 2
done

[[ -n "${GRAF_PWD}" ]] || die "Grafana password was not found in a Secret. Check: kubectl -n ${MON_NS} get secret -l app.kubernetes.io/name=grafana -o yaml"

echo
echo "==================== ACCESS ===================="
echo "Argo CD:"
echo "  URL:      http://127.0.0.1:${ARGOCD_PORT}"
echo "  Username: admin"
echo "  Password: ${ARGO_PWD:-<not-ready-yet>}"
echo
echo "Grafana:"
echo "  URL:      http://127.0.0.1:${GRAFANA_PORT}"
echo "  Username: admin"
echo "  Password: ${GRAF_PWD}"
echo "================================================="
echo
echo "Port-forwards are running in background."
echo "Logs: ${PF_DIR}/argocd.log  ${PF_DIR}/grafana.log"
echo "Stop everything: make down"