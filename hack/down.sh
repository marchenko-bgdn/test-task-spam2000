#!/usr/bin/env bash
set -euo pipefail

PROFILE="${MINIKUBE_PROFILE:-minikube}"
PF_DIR="${PF_DIR:-.portforwards}"

echo "==> Stopping port-forwards (if any)"
if [[ -d "${PF_DIR}" ]]; then
  for f in "${PF_DIR}"/*.pid; do
    [[ -e "$f" ]] || continue
    pid="$(cat "$f" || true)"
    if [[ -n "${pid}" ]] && kill -0 "${pid}" >/dev/null 2>&1; then
      kill "${pid}" >/dev/null 2>&1 || true
    fi
    rm -f "$f"
  done
fi

echo "==> Deleting minikube profile: ${PROFILE}"
minikube delete -p "${PROFILE}" || true