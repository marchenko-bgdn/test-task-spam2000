SHELL := /bin/bash

.PHONY: up down status argocd grafana logs

up:
	./hack/up.sh

down:
	./hack/down.sh

status:
	kubectl get nodes
	kubectl get pods -A
	kubectl -n argocd get applications.argoproj.io -o wide || true

argocd:
	./hack/argocd-ui.sh

grafana:
	./hack/grafana-ui.sh