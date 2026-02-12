#!/usr/bin/env bash
set -euo pipefail

echo "Grafana: http://localhost:3000"
echo "Login: admin"
echo "Password: admin (set in our values)"
kubectl -n monitoring port-forward svc/vmstack-grafana 3000:80