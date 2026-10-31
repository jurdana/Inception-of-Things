# Déroulement de l'évaluation - P1 et P2

Ce document suit la fiche de correction (`iot-correction.pdf`) dans l'ordre, et donne
pour chaque point : la commande à lancer, le résultat attendu et ce qu'il faut savoir
expliquer.

---

## 0. Avant l'arrivée du correcteur

À faire **avant** la soutenance (pas devant le correcteur) :

```bash
# Fedora 44 est-elle toujours la dernière version stable ? (la fiche le vérifie)
curl -sI https://dl.fedoraproject.org/pub/fedora/linux/releases/45/Cloud/x86_64/images/ | head -1
# 404 -> Fedora 44 reste la dernière, rien à changer
# 200 -> mettre à jour BOX_URL dans p1/Vagrantfile, p2/Vagrantfile et ~/iot-prepare.sh

VBoxManage list vms          # aucune VM pjurdanaS / pjurdanaSW qui traîne
bash ~/iot-prepare.sh        # box Fedora + K3s en cache, met à jour si nouvelle version
                             # (script hors du dépôt, gardé dans le home de la VM)
sudo -v                      # mot de passe sudo mis en cache (make net / p2-hosts en ont besoin)
```

Durées constatées : `make p1` ≈ 4 min, `make p2` ≈ 3 min 30.

---

## 1. Préliminaires (fiche p.1-2)

| Point de la fiche | Commande / action | Attendu |
|---|---|---|
| Clone dans un dossier vide | `mkdir /tmp/eval && cd /tmp/eval && git clone <repo> . && ls` | `p1 p2 p3 Makefile ...` |
| Pas d'alias malveillant | `alias; type vagrant kubectl curl` | pas d'alias, binaires dans `/usr/bin` |
| VM de 42 | montrer que l'on est sur la VM de 42 | - |
| Dossiers p1, p2, p3 | `ls p1 p2 p3` | `Vagrantfile` + `scripts/` (p1), `Vagrantfile` + `scripts/` + `confs/` (p2) |
| Scripts d'aide relus ensemble | ouvrir le `Makefile` | expliquer `net`, `p1`, `p2`, `*-clean` |

### Explications générales demandées

- **Vagrant** : outil qui décrit des VMs dans un fichier texte (`Vagrantfile`) et les
  crée avec un provider (ici VirtualBox). `vagrant up` crée et provisionne,
  `vagrant ssh` connecte, `vagrant destroy` supprime. Le provisioning lance nos scripts
  shell dans la VM au premier démarrage.
- **K3s** : distribution Kubernetes légère de Rancher, un seul binaire. Le **server**
  (controller) fait tourner le control plane (API server, scheduler, base de données
  SQLite/etcd) ; l'**agent** (worker) fait tourner les pods et rejoint le server avec
  son IP + un token. Inclut par défaut Traefik (ingress), CoreDNS, Flannel (réseau
  des pods), un load balancer (`svclb`).
- **K3d** : K3s dans des conteneurs Docker (pas de VM), pour la P3.
- **CI / Argo CD** : l'intégration continue construit et teste le code à chaque push ;
  Argo CD fait du GitOps : il surveille un dépôt Git et applique automatiquement son
  contenu au cluster (P3).

---

## 2. Partie 1 - Configuration (fiche p.2)

Ouvrir `p1/Vagrantfile` avec le correcteur et pointer chaque exigence :

| Exigence | Où dans le `Vagrantfile` |
|---|---|
| 2 machines | `config.vm.define SERVER_NAME` et `config.vm.define WORKER_NAME` |
| Dernière version stable | `BOX_URL` → Fedora **44** Cloud Base, publiée par Fedora (`dl.fedoraproject.org`) |
| Origine de la box (registre HashiCorp non garanti après 2026) | `config.vm.box_url` vers le miroir officiel Fedora |
| IP 192.168.56.110 / .111 sur une interface dédiée | `vm.network "private_network", ip: SERVER_IP / WORKER_IP` |
| Noms login + S / SW | `pjurdanaS`, `pjurdanaSW` (`vm.hostname` et `vb.name`) |
| K3s controller / agent | `scripts/server.sh` (`server`), `scripts/agent.sh` (`agent`) |
| SSH sans mot de passe | Vagrant injecte une clé SSH générée : `vagrant ssh` ne demande rien |

### Points à justifier (le correcteur va les remarquer)

- **2 CPU / 2048 Mo au lieu de 1 CPU / 512 Mo** : le sujet le *conseille* fortement mais
  ne l'impose pas. Sur la VM de 42 (virtualisation imbriquée), avec 1 vCPU le kubelet
  manque de CPU et le node passe `NotReady` ; 2 CPU / 2 Go est le minimum documenté par
  K3s pour un server.
- **Token partagé** : généré par le `Vagrantfile` (`SecureRandom.hex(32)`), stocké dans
  `p1/.vagrant/k3s_token` et passé aux deux scripts. L'agent en a besoin pour rejoindre
  le server.
- **Route par défaut via 192.168.56.1** : la commande de la fiche
  (`ip a show $(ip route | grep default ...)`) affiche l'interface qui porte la route par
  défaut. Par défaut, Vagrant la met sur l'interface NAT (10.0.2.15). Les scripts la
  déplacent sur l'interface privée, avec l'hôte comme passerelle ; `make net` fait le
  NAT sur l'hôte pour que les VMs aient internet. L'interface NAT reste pour `vagrant ssh`.
- **`--node-ip` et `--flannel-iface`** : forcent K3s à utiliser l'IP privée (sinon il
  annoncerait 10.0.2.15, la même sur les deux VMs).
- **Cache K3s (optionnel)** : si `~/.cache/iot/k3s` existe sur l'hôte (téléchargé à
  l'avance), le binaire, les images et l'installeur sont copiés dans la VM. Sinon, les
  scripts installent K3s en ligne avec l'installeur officiel (juste plus lent).
- **Dossier partagé désactivé** : la box Fedora n'a pas les guest additions ; les
  scripts sont envoyés par le provisioner.

---

## 3. Partie 1 - Usage (fiche p.2)

```bash
make p1          # ou : time make p1
```

Dans les logs : `[+] Using pre-downloaded K3s ...` sur les 2 VMs, puis à la fin les
2 nodes `Ready`.

### Server

```bash
cd p1
vagrant ssh pjurdanaS
hostname                                                  # pjurdanaS
ip a show $(ip route | grep default | awk '{print $5}')   # inet 192.168.56.110/24 (enp0s8)
systemctl status k3s --no-pager                           # active (running)
kubectl get nodes -o wide
exit
```

Sortie attendue :

```
NAME         STATUS   ROLES           ...   INTERNAL-IP      ...   OS-IMAGE
pjurdanas    Ready    control-plane   ...   192.168.56.110   ...   Fedora Linux 44 (Cloud Edition)
pjurdanasw   Ready    <none>          ...   192.168.56.111   ...   Fedora Linux 44 (Cloud Edition)
```

À expliquer :
- **2 lignes = 2 nodes dans le même cluster** : le worker a bien rejoint le server.
- `ROLES control-plane` = le server ; `<none>` = l'agent (K3s ne met pas de rôle aux
  workers).
- Noms en **minuscules** : Kubernetes impose des noms DNS en minuscules
  (`pjurdanaS` → `pjurdanas`), le hostname de la VM reste `pjurdanaS`.
- `INTERNAL-IP` = les IPs du sujet, grâce à `--node-ip`.
- `VERSION` = version de K3s, `CONTAINER-RUNTIME` = containerd embarqué dans K3s.

### Worker

```bash
vagrant ssh pjurdanaSW
hostname                                                  # pjurdanaSW
ip a show $(ip route | grep default | awk '{print $5}')   # inet 192.168.56.111/24
systemctl status k3s-agent --no-pager                     # active (running)
exit
cd ..
```

Sur le worker, `kubectl` ne marche pas : c'est normal, l'agent n'a pas d'API server ni de
kubeconfig, on administre le cluster depuis le server.

### Arrêter la P1

La P1 et la P2 utilisent le même nom (`pjurdanaS`) et la même IP (.110) : il faut
détruire la P1 avant de lancer la P2 (la fiche le prévoit : « shut down every other
running virtual machines »).

```bash
make p1-clean
VBoxManage list runningvms        # vide
```

---

## 4. Partie 2 - Configuration (fiche p.3)

Ouvrir `p2/Vagrantfile`, `p2/scripts/install_server.sh` et `p2/confs/` :

| Exigence | Où |
|---|---|
| 1 seule machine | un seul `config.vm.define SERVER_NAME` |
| Dernière version stable | même box Fedora 44 que la P1 |
| IP 192.168.56.110 | `private_network`, `ip: SERVER_IP` |
| Nom login + S | `pjurdanaS` |
| K3s en mode server | `install_server.sh` |

### Fichiers en plus (la fiche demande de les expliquer)

| Fichier | Rôle |
|---|---|
| `confs/app1.yaml` | Deployment `app1` (nginx, 1 replica) + Service ClusterIP `app1-service` |
| `confs/app2.yaml` | Deployment `app2` (`nginxdemos/hello`, **3 replicas**) + Service `app2-service` |
| `confs/app3.yaml` | Deployment `app3` (httpd, 1 replica) + Service `app3-service` |
| `confs/ingress.yaml` | Ingress Traefik : routage selon le HOST |
| `scripts/install_server.sh` | réseau, installation K3s, `kubectl apply` des confs, attente que tout réponde |

Les manifests sont envoyés dans la VM par le provisioner `file` (`/tmp/p2-confs`), puis
appliqués avec `kubectl apply -R -f`.

---

## 5. Partie 2 - Usage (fiche p.3)

```bash
make p2          # demande le mot de passe sudo (make net + /etc/hosts)
```

Dans les logs, dans l'ordre :

```
[+] Using pre-downloaded K3s v1.36.5+k3s1
[+] Deploying app1, app2, app3 and the ingress
[+] Waiting for Traefik to serve the ingress on 192.168.56.110:80
[+] Apps deployed on 192.168.56.110
```

Quand `Apps deployed` s'affiche, tout répond déjà : le script attend une vraie réponse
HTTP avant de finir (le job Helm qui installe Traefik échoue souvent une fois au
démarrage, puis K3s le relance).

### Dans la VM

```bash
cd p2
vagrant ssh pjurdanaS
hostname                                                  # pjurdanaS
ip a show $(ip route | grep default | awk '{print $5}')   # inet 192.168.56.110/24
systemctl status k3s --no-pager                           # active (running)
kubectl get nodes -o wide                                 # 1 node pjurdanas, control-plane, 192.168.56.110
kubectl get all
```

`kubectl get all` attendu, et à expliquer ligne par ligne :

```
pod/app1-...          1/1 Running        <- 1 pod pour app1
pod/app2-... (x3)     1/1 Running        <- 3 replicas d'app2, comme demandé
pod/app3-...          1/1 Running
service/app1-service  ClusterIP  80/TCP  <- IP interne stable devant les pods
service/app2-service  ClusterIP  80/TCP     (répartit entre les 3 pods d'app2)
service/app3-service  ClusterIP  80/TCP
service/kubernetes    ClusterIP  443/TCP <- l'API server
deployment.apps/app1  1/1                <- état voulu (nb de replicas, image)
deployment.apps/app2  3/3
deployment.apps/app3  1/1
replicaset.apps/...                      <- créé par le deployment, maintient le nb de pods
```

- **Pod** : un ou plusieurs conteneurs, plus petite unité de Kubernetes, IP éphémère.
- **ReplicaSet** : garantit qu'il y a toujours N pods (supprimer un pod → il est recréé).
- **Deployment** : gère les ReplicaSets (mises à jour progressives, rollback).
- **Service** : IP et nom DNS stables devant des pods choisis par label (`app: app2`),
  avec répartition de charge.

### Montrer l'Ingress (« la commande n'est volontairement pas donnée »)

```bash
kubectl get ingress
kubectl describe ingress app-ingress
```

```
NAME          CLASS     HOSTS                                    ADDRESS          PORTS
app-ingress   traefik   app1.com,app2.com,app3.com + 1 more...   192.168.56.110   80
```

```
Rules:
  Host        Path  Backends
  app1.com    /     app1-service:80
  app2.com    /     app2-service:80
  app3.com    /     app3-service:80
  *           /     app3-service:80      <- règle sans host = app3 par défaut
```

À expliquer :
- L'**Ingress** est une règle de routage HTTP ; c'est **Traefik** (installé d'office par
  K3s, `ingressClassName: traefik`) qui l'applique.
- Traefik écoute sur le port 80 de 192.168.56.110 (service LoadBalancer + `svclb`),
  lit l'en-tête `Host` de la requête et l'envoie au bon service.
- La dernière règle n'a **pas de host** : elle attrape tout le reste → app3 par défaut,
  comme le demande le sujet.
- `+ 1 more...` = cette règle sans host (`*`).

Optionnel, pour montrer Traefik : `kubectl -n kube-system get pods,svc | grep traefik`.

```bash
exit
cd ..
```

### Tester l'accès selon le HOST (depuis l'hôte)

```bash
curl -H "Host: app1.com" 192.168.56.110          # Welcome to nginx!          -> app1
curl -H "Host: app2.com" 192.168.56.110          # Server name: app2-xxxx-yyy -> app2
curl -H "Host: app2.com" 192.168.56.110          # relancer : le Server name change (3 replicas)
curl -H "Host: app3.com" 192.168.56.110          # It works! (httpd)          -> app3
curl 192.168.56.110                              # It works!  -> app3 par défaut
curl -H "Host: nimporte.com" 192.168.56.110      # It works!  -> app3 par défaut
```

Avec les noms (`make p2` a ajouté `192.168.56.110 app1.com app2.com app3.com` à
`/etc/hosts`) : `curl app1.com`, `curl app2.com`, ou dans le navigateur
`http://app1.com`, `http://app2.com`, `http://192.168.56.110`.

Démo bonus de la résilience (si le correcteur est curieux) :

```bash
vagrant ssh pjurdanaS -c "kubectl delete pod -l app=app2 --wait=false; kubectl get pods -w"
# les 3 pods d'app2 sont recréés automatiquement par le ReplicaSet (Ctrl+C pour sortir)
```

### Fin de la P2

```bash
make p2-clean
grep app1.com /etc/hosts      # vide
```

---

## 6. Questions probables

| Question | Réponse |
|---|---|
| Différence server / agent ? | Le server porte le control plane (API, scheduler, base) ; l'agent exécute seulement les pods (kubelet + containerd) et rejoint le server avec le token. |
| Comment l'agent rejoint-il le cluster ? | `K3S_URL=https://192.168.56.110:6443` + `K3S_TOKEN` partagé, généré par le Vagrantfile. |
| Pourquoi désactiver firewalld ? | Il bloque les ports de K3s : 6443 (API), 8472/udp (Flannel VXLAN), 10250 (kubelet). |
| Pourquoi `--write-kubeconfig-mode=644` ? | Pour que l'utilisateur `vagrant` lance `kubectl` sans sudo. |
| Pourquoi Fedora ? Et SELinux ? | Distribution à jour avec box officielle. SELinux reste actif : l'installeur K3s ajoute le paquet `k3s-selinux`. |
| Ingress vs Service ? | Le Service expose des pods à l'intérieur du cluster (L4) ; l'Ingress route le HTTP venant de l'extérieur selon le host/chemin (L7) vers les Services. |
| Pourquoi des Services ClusterIP et pas NodePort ? | Seul Traefik est exposé (port 80) ; les applis restent internes et passent par l'Ingress. |
| Où sont les images Docker ? | Tirées de Docker Hub au démarrage des pods (`nginx:alpine`, `nginxdemos/hello:plain-text`, `httpd:alpine`). |
| Que fait `make net` ? | Active le routage IP sur l'hôte et un NAT (nftables) pour 192.168.56.0/24, plus des règles pour passer à travers Docker s'il est installé. |

---

## 7. Si ça casse pendant l'éval

```bash
# Pas d'internet dans la VM ("no internet through 192.168.56.1")
make net
sudo nft list table ip iot_nat

# Le node n'est pas Ready / K3s ne démarre pas (dans la VM)
sudo journalctl -u k3s --no-pager | tail -50        # k3s-agent sur le worker
sudo ausearch -m avc -ts recent                      # refus SELinux

# Une VM d'une autre partie traîne (conflit de nom / d'IP 192.168.56.110)
VBoxManage list runningvms
make p1-clean   # ou make p2-clean

# curl app1.com ne répond pas mais curl -H "Host: app1.com" 192.168.56.110 oui
grep app1.com /etc/hosts       # sinon : make p2-hosts
```
