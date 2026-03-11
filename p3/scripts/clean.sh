#!/bin/bash

echo "cluster suppression"
k3d cluster delete p3-cluster

echo "cleaning the configuration of kubeconfig"

kubectl config delete-cluster k3d-p3-cluster 2>/dev/null || true
kubectl config delete-context k3d-p3-cluster 2>/dev/null || true