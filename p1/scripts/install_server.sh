#!/bin/bash

sudo apt-get update && sudo apt-get install -y curl

curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --node-ip 192.168.56.110" sh -

sleep 5

echo "Server K3s installed"