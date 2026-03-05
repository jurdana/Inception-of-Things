#!/bin/bash

NODE_TOKEN=$1
MASTER_IP="192.168.56.110"

sudo apt-get update && sudo apt-get install -y curl

curl -sfL https://get.k3s.io | K3S_URL=https://${MASTER_IP}:6443 K3S_TOKEN=${NODE_TOKEN} sh -

echo "Worker connected to Server"