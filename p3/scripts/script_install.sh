#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P3_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo -e '\033[0;32m' "Starting installation process..." '\033[1;37m' 


# __________________Update pachage
echo -e '\033[0;32m' "Updating package list..." '\033[1;37m'
sudo apt-get update -y


# __________________Installation of k3d
echo -e '\033[0;32m' "Installing k3d..." '\033[1;37m'
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash


# __________________Installation of docker
echo -e '\033[0;32m' "Installing docker.io..." '\033[1;37m'
sudo apt install -y docker.io


# __________________Update /etc/hots for P3
echo -e  '\033[0;32m' "Updating /etc/hosts..." '\033[1;37m'
echo "127.0.0.1 argocd.local"  | sudo tee -a /etc/hosts
echo "127.0.0.1 wil42.local"   | sudo tee -a /etc/hosts


# __________________Enable & start of docker
echo -e '\033[0;32m' "Starting and enabling docker service..." '\033[1;37m'
sudo systemctl start docker
sudo systemctl enable docker
echo -e '\033[0;32m' "Adding user to docker group..." '\033[1;37m'
sudo usermod -aG docker $USER


# __________________Installation of kubectl
echo -e '\033[0;32m' "Installing kubectl..." '\033[1;37m'
curl -LO https://dl.k8s.io/release/v1.35.0/bin/linux/amd64/kubectl
chmod +x kubectl
sudo mv kubectl /usr/local/bin/kubectl


# __________________Creating k3d cluster
echo -e '\033[0;32m' "Creating k3d cluster 'mycluster'..." '\033[1;37m'
sg docker -c "k3d cluster create mycluster -p \"80:80@loadbalancer\" -p \"443:443@loadbalancer\""


# __________________Installation of ArgoCD
echo -e '\033[0;32m' "Installing ArgoCD..." '\033[1;37m'
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
echo -e '\033[0;32m' "Waiting for ArgoCD to be ready..." '\033[1;37m'
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd


# __________________Configuration for ArgoCD insecure mode
echo -e '\033[0;32m' "Configuring ArgoCD for insecure HTTP access..." '\033[1;37m'
kubectl patch deployment argocd-server -n argocd --type='json' -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--insecure"}]'
kubectl rollout status deployment/argocd-server -n argocd


# __________________Deploying ArgoCD application & ingress
echo -e '\033[0;32m' "Deploying ArgoCD Application..." '\033[1;37m'
kubectl apply -f "${P3_DIR}/argocd/argocd-basic.yaml"
echo -e '\033[0;32m' "Deploying ArgoCD Ingress..." '\033[1;37m'
kubectl apply -f "${P3_DIR}/argocd/argocd-ingress.yaml"


# __________________Create a temporary file Password to store ArgoCD password
echo -e '\033[0;32m' "Retrieving ArgoCD admin password..." '\033[1;37m'
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d > "${P3_DIR}/argocd/Password"
echo "" >> "${P3_DIR}/argocd/Password"


echo -e '\033[0;32m' "Installation complete!" '\033[1;37m'
echo "Note: You may need to log out and back in for docker group changes to take effect."
