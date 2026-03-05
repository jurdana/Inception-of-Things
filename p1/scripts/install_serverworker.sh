#!/bin/bash

NODE_TOKEN=$1
MASTER_IP="192.168.56.110"
WORKER_IP="192.168.56.111"

sudo apt-get update && sudo apt-get install -y curl

curl -sfL https://get.k3s.io | K3S_URL=https://${MASTER_IP}:6443 K3S_TOKEN=${NODE_TOKEN} sh -s - agent --node-ip ${WORKER_IP}

echo "Worker connected to Server with IP ${WORKER_IP}"