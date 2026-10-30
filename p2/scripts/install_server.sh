#!/usr/bin/env bash
# Provisioning script for the p2 K3s server, run as root by Vagrant.
# Inputs (environment variables set by the Vagrantfile):
#   NODE_IP   - private IP of this machine (192.168.56.110)
#   GATEWAY   - host IP on the private network (192.168.56.1), used as default route
#   CONFS_DIR - directory holding the uploaded Kubernetes manifests

# Strict mode: stop on error, undefined variable, or failed pipeline (e.g. curl | sh)
set -euo pipefail

# Fail early with a clear message if the Vagrantfile did not pass a variable
: "${NODE_IP:?NODE_IP is required}"
: "${GATEWAY:?GATEWAY is required}"
: "${CONFS_DIR:?CONFS_DIR is required}"

# Full path to kubectl (symlink created by the K3s installer, not in sudo's PATH)
KUBECTL=/usr/local/bin/kubectl

# --- Interfaces --------------------------------------------------------------
# Same detection as p1/scripts/server.sh: private interface (holds NODE_IP)
# and NAT interface (holds 10.0.2.x)
IFACE="$(ip -o -4 addr show | awk -v ip="${NODE_IP}" '{split($4, a, "/"); if (a[1] == ip && !f) {print $2; f = 1}}')"
NAT_IFACE="$(ip -o -4 addr show | awk '{split($4, a, "/"); if (a[1] ~ /^10\.0\.2\./ && !f) {print $2; f = 1}}')"
if [[ -z "${IFACE}" || -z "${NAT_IFACE}" ]]; then
    echo "[ERROR] interfaces not found (private: '${IFACE}', nat: '${NAT_IFACE}')" >&2
    exit 1
fi
echo "[+] Private interface: ${IFACE} / NAT interface: ${NAT_IFACE}"

# --- Default route through the private network -------------------------------
# Same logic as p1 (see p1/scripts/server.sh for details): restore SELinux
# labels on the NetworkManager profiles, then keep a single default route via
# the host (GATEWAY), which NATs the private network (`make net`)
restorecon -R /etc/NetworkManager/system-connections
NAT_CON="$(nmcli -g GENERAL.CONNECTION device show "${NAT_IFACE}")"
PRIV_CON="$(nmcli -g GENERAL.CONNECTION device show "${IFACE}")"
nmcli connection modify "${NAT_CON}" ipv4.never-default yes ipv6.never-default yes
nmcli connection modify "${PRIV_CON}" ipv4.gateway "${GATEWAY}"
nmcli device reapply "${NAT_IFACE}"
nmcli device reapply "${IFACE}"
ip route del default via 10.0.2.2 dev "${NAT_IFACE}" 2>/dev/null || true

echo "[+] Checking internet access via ${GATEWAY}"
for i in $(seq 1 10); do
    curl -sSf --max-time 5 -o /dev/null https://get.k3s.io && break
    if [[ $i -eq 10 ]]; then
        echo "[ERROR] no internet through ${GATEWAY}: run 'make net' on the host" >&2
        exit 1
    fi
    sleep 3
done

# --- K3s ---------------------------------------------------------------------
# Disable firewalld if present: it blocks K3s ports and the ingress (80/tcp)
systemctl disable --now firewalld 2>/dev/null || true

# Same cache logic as p1/scripts/server.sh: files from prepare_host.sh,
# else online installer
K3S_CACHE=/tmp/k3s-cache
if [[ -f "${K3S_CACHE}/k3s" ]]; then
    echo "[+] Using pre-downloaded K3s $(cat "${K3S_CACHE}/version")"
    install -m 755 "${K3S_CACHE}/k3s" /usr/local/bin/k3s
    install -D -m 644 "${K3S_CACHE}/k3s-airgap-images-amd64.tar.zst" \
        /var/lib/rancher/k3s/agent/images/k3s-airgap-images-amd64.tar.zst
    INSTALL_SH="${K3S_CACHE}/install.sh"
    export INSTALL_K3S_SKIP_DOWNLOAD=binary
else
    curl -sSfL https://get.k3s.io -o /tmp/k3s-install.sh
    INSTALL_SH=/tmp/k3s-install.sh
fi

echo "[+] Installing K3s server"
# Official installer, single node: Traefik (bundled with K3s) is the ingress
# controller that routes requests to app1/app2/app3 by HOST header
INSTALL_K3S_EXEC="server --node-ip=${NODE_IP} --flannel-iface=${IFACE} --write-kubeconfig-mode=644" \
    sh "${INSTALL_SH}"

# Kubernetes stores node names in lowercase (pjurdanaS -> pjurdanas)
NODE="$(hostname | tr '[:upper:]' '[:lower:]')"
echo "[+] Waiting for node ${NODE}"
for _ in $(seq 1 60); do
    "${KUBECTL}" get node "${NODE}" &>/dev/null && break
    sleep 2
done
"${KUBECTL}" wait --for=condition=Ready "node/${NODE}" --timeout=180s

# --- Applications ------------------------------------------------------------
echo "[+] Deploying app1, app2, app3 and the ingress"
# -R: the file provisioner nests the folder on re-provision (/tmp/p2-confs/confs)
"${KUBECTL}" apply -R -f "${CONFS_DIR}"
# Instead of a fixed sleep: wait until every deployment has its replicas up
"${KUBECTL}" wait --for=condition=Available deployment --all --timeout=300s

echo "[+] Apps deployed on ${NODE_IP}"
