#!/bin/bash

sudo apt-get purge -y docker.io
sudo apt-get autoremove -y

sudo rm -rf /etc/docker /var/lib/docker

sudo rm /usr/local/bin/kubectl
sudo rm /usr/local/bin/k3d

rm -rf ~/.kube ~/.docker