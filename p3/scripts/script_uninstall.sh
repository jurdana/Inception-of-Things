#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P3_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "Starting uninstallation process..."


# __________________Delete dev namespace
echo "Removing dev namespace and deployed applications..."
kubectl delete namespace dev --ignore-not-found=true || true


# __________________Delete ArgoCD resources and namespace
echo "Removing ArgoCD from Kubernetes..."
kubectl delete namespace argocd --ignore-not-found=true || true


# __________________Delete k3d cluster
echo "Deleting k3d cluster 'mycluster'..."
sg docker -c "k3d cluster delete mycluster" || sudo k3d cluster delete mycluster || true


# __________________Remove kubectl
echo "Removing kubectl..."
sudo rm /usr/local/bin/kubectl || true


# __________________Remove user from docker group
echo "Removing user from docker group..."
sudo gpasswd -d $USER docker || true


# __________________Stop and disable docker
echo "Stopping and disabling docker..."
sudo systemctl stop docker || true
sudo systemctl disable docker || true


# __________________Uninstall docker.io
echo "Uninstalling docker.io..."
sudo apt-get remove -y docker.io
sudo apt-get purge -y docker.io
sudo apt-get autoremove -y


# __________________Uninstall k3d
echo "Removing k3d..."
sudo rm /usr/bin/k3d || true


# __________________Delete password file
rm -f "${P3_DIR}/argocd/Password"


# __________________Remove the hosts from /etc/hosts
sudo sed -i '/argocd\.local/d' /etc/hosts
sudo sed -i '/wil42\.local/d' /etc/hosts


echo "Uninstallation complete!"
echo "Note: You may need to log out and back in for group changes to take effect."
