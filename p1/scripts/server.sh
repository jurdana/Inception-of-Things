#!/usr/bin/env bash
# Provisioning script for the K3s server (controller), run as root by Vagrant.
# Inputs (environment variables set by the Vagrantfile):
#   NODE_IP   - private IP of this machine (192.168.56.110)
#   GATEWAY   - host IP on the private network (192.168.56.1), used as default route
#   K3S_TOKEN - shared secret the agent will use to join the cluster

# Strict mode: stop on error, undefined variable, or failed pipeline (e.g. curl | sh)
set -euo pipefail

# Fail early with a clear message if the Vagrantfile did not pass a variable
: "${NODE_IP:?NODE_IP is required}"
: "${GATEWAY:?GATEWAY is required}"
: "${K3S_TOKEN:?K3S_TOKEN is required}"

# Full path to kubectl (symlink created by the K3s installer, not in sudo's PATH)
KUBECTL=/usr/local/bin/kubectl

# --- Interfaces --------------------------------------------------------------
# Private interface: the one holding NODE_IP (enp0s8, eth1... depends on the box).
# awk reads the whole input and keeps the first match: exiting early would kill
# `ip` with SIGPIPE, and pipefail would then abort the script silently.
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
# The subject's IP must be on the primary interface, i.e. the one holding the
# default route. We keep a single default route via the host (GATEWAY), which
# NATs the private network to the internet (see `make net` on the host).
# NetworkManager connection (profile) names attached to each interface
NAT_CON="$(nmcli -g GENERAL.CONNECTION device show "${NAT_IFACE}")"
PRIV_CON="$(nmcli -g GENERAL.CONNECTION device show "${IFACE}")"
# never-default: NetworkManager stops installing a default route on the NAT
# interface, even after a DHCP renewal (the NAT stays usable for vagrant ssh)
nmcli connection modify "${NAT_CON}" ipv4.never-default yes ipv6.never-default yes
# Private interface uses the host as gateway
nmcli connection modify "${PRIV_CON}" ipv4.gateway "${GATEWAY}"
# Apply live without bringing interfaces down (would cut the vagrant ssh session)
nmcli device reapply "${NAT_IFACE}"
nmcli device reapply "${IFACE}"
# Remove the NAT default route if it is still present
ip route del default via 10.0.2.2 dev "${NAT_IFACE}" 2>/dev/null || true

# Check internet access through the host before installing anything
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
# Disable firewalld if present: it blocks K3s ports (6443/tcp, 8472/udp, 10250/tcp)
systemctl disable --now firewalld 2>/dev/null || true

echo "[+] Installing K3s server"
# Official installer:
#   server                       -> controller (control plane)
#   --node-ip                    -> IP announced to the cluster (not the NAT one)
#   --flannel-iface              -> pod network (VXLAN) through the private interface
#   --write-kubeconfig-mode=644  -> kubectl usable by the vagrant user without sudo
curl -sSfL https://get.k3s.io | \
    K3S_TOKEN="${K3S_TOKEN}" \
    INSTALL_K3S_EXEC="server --node-ip=${NODE_IP} --flannel-iface=${IFACE} --write-kubeconfig-mode=644" \
    sh -

# Kubernetes stores node names in lowercase (pjurdanaS -> pjurdanas)
NODE="$(hostname | tr '[:upper:]' '[:lower:]')"
echo "[+] Waiting for node ${NODE}"
# Wait for the node object to be registered (up to 60 x 2s)
for _ in $(seq 1 60); do
    "${KUBECTL}" get node "${NODE}" &>/dev/null && break
    sleep 2
done
# Then wait until it reports Ready (fails after 180s)
"${KUBECTL}" wait --for=condition=Ready "node/${NODE}" --timeout=180s

echo "[+] K3s server ready on ${NODE_IP}"