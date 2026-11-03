#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BONUS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
P3_DIR="$(cd "${BONUS_DIR}/../p3" && pwd)"

echo "Starting bonus uninstallation..."

# __________________Give Argo CD back its p3 source (GitHub) while it still exists
if kubectl get namespace argocd &>/dev/null; then
    echo "Restoring the p3 Argo CD Application..."
    kubectl apply -f "${P3_DIR}/argocd/argocd-basic.yaml" || true
fi

# __________________GitLab release, PostgreSQL, Redis, secrets and volumes
# Deleting the namespace removes everything created in it
echo "Removing GitLab..."
helm uninstall gitlab -n gitlab --ignore-not-found || true
kubectl delete namespace gitlab --ignore-not-found=true || true

# __________________Helm
echo "Removing Helm..."
sudo rm -f /usr/local/bin/helm
rm -rf ~/.config/helm ~/.cache/helm ~/.local/share/helm

# __________________Generated files and hosts entry
rm -f "${BONUS_DIR}/confs/gitlab/Password"
sudo sed -i '/gitlab\.local/d' /etc/hosts

echo "Bonus uninstallation complete!"
