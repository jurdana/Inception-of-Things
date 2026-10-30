#!/usr/bin/env bash
# Provisioning script for the K3s agent (worker), run as root by Vagrant.
# Inputs (environment variables set by the Vagrantfile):
#   NODE_IP   - private IP of this machine (192.168.56.111)
#   SERVER_IP - private IP of the K3s server (192.168.56.110)
#   GATEWAY   - host IP on the private network (192.168.56.1), used as default route
#   K3S_TOKEN - shared secret, same value as on the server

# Strict mode: stop on error, undefined variable, or failed pipeline
set -euo pipefail

# Fail early if a required variable is missing
: "${NODE_IP:?NODE_IP is required}"
: "${SERVER_IP:?SERVER_IP is required}"
: "${GATEWAY:?GATEWAY is required}"
: "${K3S_TOKEN:?K3S_TOKEN is required}"

# --- Interfaces --------------------------------------------------------------
# Private interface (holds NODE_IP) and NAT interface (holds 10.0.2.x)
IFACE="$(ip -o -4 addr show | awk -v ip="${NODE_IP}" '{split($4, a, "/"); if (a[1] == ip && !f) {print $2; f = 1}}')"
NAT_IFACE="$(ip -o -4 addr show | awk '{split($4, a, "/"); if (a[1] ~ /^10\.0\.2\./ && !f) {print $2; f = 1}}')"
if [[ -z "${IFACE}" || -z "${NAT_IFACE}" ]]; then
    echo "[ERROR] interfaces not found (private: '${IFACE}', nat: '${NAT_IFACE}')" >&2
    exit 1
fi
echo "[+] Private interface: ${IFACE} / NAT interface: ${NAT_IFACE}"

# --- Default route through the private network -------------------------------
# Vagrant copies the private interface profile from /tmp, so the file keeps a
# /tmp SELinux label and NetworkManager is denied rewriting it: restore the
# correct labels on the NetworkManager profiles directory.
restorecon -R /etc/NetworkManager/system-connections
# Same logic as server.sh: single default route via the host (GATEWAY)
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
# Disable firewalld if present so the agent can reach and be reached by the server
systemctl disable --now firewalld 2>/dev/null || true

echo "[+] Waiting for K3s API on ${SERVER_IP}:6443"
# Poll the server API up to 60 x 2s; any HTTP answer (even 401) means it is up
for i in $(seq 1 60); do
    curl -sk -o /dev/null --max-time 2 "https://${SERVER_IP}:6443" && break
    if [[ $i -eq 60 ]]; then
        echo "[ERROR] K3s server unreachable" >&2
        exit 1
    fi
    sleep 2
done

# Same cache logic as server.sh: files from prepare_host.sh, else online installer
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

echo "[+] Installing K3s agent"
# Official installer in agent mode:
#   K3S_URL         -> server API address (switches the installer to agent mode)
#   K3S_TOKEN       -> shared secret proving the agent may join this cluster
#   agent           -> worker (kubelet + pods, no control plane)
#   --node-ip       -> announce the private IP instead of the NAT one
#   --flannel-iface -> pod traffic through the private interface
K3S_URL="https://${SERVER_IP}:6443" \
    K3S_TOKEN="${K3S_TOKEN}" \
    INSTALL_K3S_EXEC="agent --node-ip=${NODE_IP} --flannel-iface=${IFACE}" \
    sh "${INSTALL_SH}"

echo "[+] K3s agent joined ${SERVER_IP}"