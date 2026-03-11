#!/bin/bash

set -e

sudo apt-get update -y

sudo apt-get install -y curl wget docker.io

curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"

sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

rm kubectl

sudo usermod -aG docker $USER

echo "Tools installation complete"