P1_DIR = p1
P2_DIR = p2
P3_DIR = p3

P1_SERVER = pjurdanaS
P1_WORKER = pjurdanaSW

P2_SERVER = pjurdanaS

P3_NAME = p3-cluster
SCRIPTS_PATH = ./p3/scripts

NET_CIDR  = 192.168.56.0/24
NFT_TABLE = iot_nat

.PHONY: net net-clean \
		p1 p1-status p1-clean \
		p2 p2-up p2-status p2-clean p2-hosts \
		p3-install p3-clean


# Host routes the private network (192.168.56.0/24) to the internet:
# VMs use 192.168.56.1 (this host) as default gateway.
net:
	sudo sysctl -qw net.ipv4.ip_forward=1
	sudo nft delete table ip $(NFT_TABLE) 2>/dev/null || true
	sudo nft add table ip $(NFT_TABLE)
	sudo nft add chain ip $(NFT_TABLE) postrouting '{ type nat hook postrouting priority srcnat; policy accept; }'
	sudo nft add rule ip $(NFT_TABLE) postrouting ip saddr $(NET_CIDR) ip daddr != $(NET_CIDR) masquerade
# Docker sets the FORWARD policy to DROP: let the private network through it
	if sudo iptables -n -L DOCKER-USER >/dev/null 2>&1; then \
		sudo iptables -C DOCKER-USER -s $(NET_CIDR) -j ACCEPT 2>/dev/null || \
			sudo iptables -I DOCKER-USER -s $(NET_CIDR) -j ACCEPT; \
		sudo iptables -C DOCKER-USER -d $(NET_CIDR) -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
			sudo iptables -I DOCKER-USER -d $(NET_CIDR) -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT; \
	fi

# ip_forward is left on: Docker (p3) needs it too
net-clean:
	sudo nft delete table ip $(NFT_TABLE) 2>/dev/null || true
	-sudo iptables -D DOCKER-USER -s $(NET_CIDR) -j ACCEPT 2>/dev/null
	-sudo iptables -D DOCKER-USER -d $(NET_CIDR) -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null

p1: net
	cd $(P1_DIR) && vagrant up
# The agent finishes before its node is registered: wait for both nodes Ready
	cd $(P1_DIR) && vagrant ssh $(P1_SERVER) -c "timeout 120 sh -c 'until [ \$$(kubectl get nodes --no-headers 2>/dev/null | wc -l) -ge 2 ]; do sleep 2; done' && kubectl wait --for=condition=Ready node --all --timeout=180s"
	cd $(P1_DIR) && vagrant ssh $(P1_SERVER) -c "kubectl get nodes -o wide"

p1-status:
	cd $(P1_DIR) && vagrant ssh $(P1_SERVER) -c "kubectl get nodes -o wide"

p1-clean:
	cd $(P1_DIR) && vagrant destroy -f
	rm -rf $(P1_DIR)/.vagrant

# ______________________________________________________________________________________________________________________________________________________________________________________________________________________

p2: net p2-up p2-hosts p2-status

p2-up:
	@echo "P2 launch."
	cd $(P2_DIR) && vagrant up

p2-hosts:
	@echo "Configuration of /etc/hosts on the host"
	@grep -q "192.168.56.110 app1.com" /etc/hosts || \
		echo "192.168.56.110 app1.com app2.com app3.com" | sudo tee -a /etc/hosts

p2-status:
	@echo "Node status"
	@echo "\n--- NODES ---"
	cd $(P2_DIR) && vagrant ssh $(P2_SERVER) -c "kubectl get nodes -o wide"
	
	@echo "\n--- DEPLOYMENTS ---"
	cd $(P2_DIR) && vagrant ssh $(P2_SERVER) -c "kubectl get deployments"

	@echo "\n--- PODS ---"
	cd $(P2_DIR) && vagrant ssh $(P2_SERVER) -c "kubectl get pods -o wide"

	@echo "\n--- SERVICES ---"
	cd $(P2_DIR) && vagrant ssh $(P2_SERVER) -c "kubectl get services"

	@echo "\n--- INGRESS ---"
	cd $(P2_DIR) && vagrant ssh $(P2_SERVER) -c "kubectl get ingress"

p2-clean:
	cd $(P2_DIR) && vagrant destroy -f
	rm -rf $(P2_DIR)/.vagrant
	@echo "hosts suppression"
	@sudo sed -i '/192.168.56.110 app1.com/d' /etc/hosts

# ______________________________________________________________________________________________________________________________________________________________________________________________________________________


p3-install:
	./p3/scripts/script_install.sh

p3-clean:
	./p3/scripts/script_uninstall.sh

