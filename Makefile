P1_DIR = p1
P2_DIR = p2
P3_DIR = p3

P1_SERVER = pjurdanaS
P1_WORKER = pjurdanaSW

.PHONY: p1 p1-up p1-join p1-clean

# P1 part

p1: p1-up p1-join p1-status

p1-up:
	@echo "P1 launch."
	cd $(P1_DIR) && vagrant up

p1-join:
	@echo "Join of P1 worker"
	$(eval TOKEN=$(shell cd $(P1_DIR) && vagrant ssh $(P1_SERVER) -c "sudo cat /var/lib/rancher/k3s/server/node-token" | tr -d '\r'))
	cd $(P1_DIR) && vagrant ssh $(P1_WORKER) -c "sudo bash /vagrant/scripts/install_serverworker.sh $(TOKEN)"

p1-status:
	@echo "Node status"
	cd $(P1_DIR) && vagrant ssh $(P1_SERVER) -c "sudo kubectl get nodes"

p1-clean:
	cd $(P1_DIR) && vagrant destroy -f
	rm -rf $(P1_DIR)/.vagrant
