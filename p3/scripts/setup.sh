#!/bin/bash

set -e

k3d cluster create p3-cluster -p "8888:80@loadbalancer" --agents 2

kubectl create namespace argocd
kubectl create namespace dev

kubectl apply --server-side -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
sleep 20
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s

kubectl apply -f p3/confs/application.yaml

echo "cluster setup complete"