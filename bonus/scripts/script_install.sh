#!/bin/bash

#____Make Sure P3 is Launch:
if ! kubectl get namespace argocd &>/dev/null; then
    echo "[ERROR] p3 is not installed: run 'make p3-install' first" >&2
    exit 1
fi
kubectl wait --for=condition=available --timeout=60s deployment/argocd-server -n argocd

#___Installation of Helm
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4 | bash
helm version

#___Creation of namespace for Redis and Postresql Installation
kubectl create namespace gitlab
kubectl apply --dry-run=server -f bonus/confs/gitlab/postgresql.yaml
kubectl apply --dry-run=server -f bonus/confs/gitlab/redis.yaml
for app in gitlab-postgresql gitlab-redis; do
    until kubectl get pod -n gitlab -l app="${app}" -o name | grep -q .; do sleep 2; done
    kubectl wait --for=condition=Ready pod -l app="${app}" -n gitlab --timeout=300s
