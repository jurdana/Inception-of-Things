P1_DIR = p1
P2_DIR = p2
P3_DIR = p3

P1_SERVER = pjurdanaS
P1_WORKER = pjurdanaSW

P2_SERVER = pjurdanaS

P3_NAME = p3-cluster


.PHONY: p1 p1-up p1-join p1-status p1-clean \
		p2 p2-up p2-status p2-clean p2-hosts \
		p3

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

# ______________________________________________________________________________________________________________________________________________________________________________________________________________________

p2: p2-up p2-hosts p2-status

p2-up:
	@echo "P2 launch."
	cd $(P2_DIR) && vagrant up

p2-hosts:
	@echo "Configuration of /etc/hosts on the host"
	@echo "192.168.56.110 app1.com app2.com app3.com" | sudo tee -a /etc/hosts

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

p3:
	@echo "P3 launch"
	k3d cluster create $(P3_NAME) --api-port 6443 -p "8888:30008@agent:0" --agent 2

	kubectl create namespace argocd
	kubectl create namespace dev

	kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

	@echo "Waiting argoCD ready status"
	kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s
	@echo "ArgoCD installed, Use 'make p3-pass' to get the admin pass"

p3-clean:
	k3d cluster delete $(P3_NAME)

p3-pass:
	@echo "The admin pass for argoCD is:"
	kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo