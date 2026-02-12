#!/usr/bin/env bash
set -euo pipefail

echo "Argo CD: http://localhost:8080"
echo -n "Admin password: "
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo
kubectl -n argocd port-forward svc/argocd-server 8080:80