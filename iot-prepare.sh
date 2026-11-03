#!/usr/bin/env bash
# One-time host preparation, to run once before building p1/p2.
# Downloads everything that survives `make p1-clean` / `make p2-clean`, so that
# `vagrant up` does not fetch it again on every build:
#   - the Fedora 44 Vagrant box (Vagrant box cache, ~/.vagrant.d/boxes)
#   - the K3s binary, installer and airgap images (~/.cache/iot/k3s), uploaded
#     into the VMs by the Vagrantfiles instead of being downloaded by each VM
# Both live outside the repository, so they are kept across `git clone`.
# Safe to run again: only what is missing or outdated is downloaded.

# Strict mode: stop on error, undefined variable, or failed pipeline
set -euo pipefail

# Same box as p1/Vagrantfile and p2/Vagrantfile
BOX_NAME="fedora44"
BOX_URL="https://dl.fedoraproject.org/pub/fedora/linux/releases/44/Cloud/x86_64/images/Fedora-Cloud-Base-Vagrant-VirtualBox-44-1.7.x86_64.vagrant.virtualbox.box"

# Same path as K3S_CACHE in the Vagrantfiles
CACHE_DIR="${HOME}/.cache/iot/k3s"
ARCH="amd64"

# --- Vagrant box -------------------------------------------------------------
# `vagrant box list` prints "fedora44 (virtualbox, 0)"
if vagrant box list | grep -q "^${BOX_NAME} "; then
    echo "[+] Box ${BOX_NAME} already present"
else
    echo "[+] Adding box ${BOX_NAME}"
    vagrant box add --name "${BOX_NAME}" "${BOX_URL}"
fi

# --- K3s ---------------------------------------------------------------------
# Latest stable K3s version: the stable channel redirects to the release page
# (.../releases/tag/v1.xx.y+k3s1), same lookup as the official installer
VERSION="$(curl -sSfL -o /dev/null -w '%{url_effective}' https://update.k3s.io/v1-release/channels/stable)"
VERSION="${VERSION##*/}"

if [[ -f "${CACHE_DIR}/version" && "$(cat "${CACHE_DIR}/version")" == "${VERSION}" ]]; then
    echo "[+] K3s ${VERSION} already cached in ${CACHE_DIR}"
    exit 0
fi

echo "[+] Downloading K3s ${VERSION}"
# Download into a temporary directory, so an interrupted run never leaves a
# half-filled cache behind (the Vagrantfiles only check that it exists)
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
# "+" must be URL-encoded in GitHub release URLs
BASE="https://github.com/k3s-io/k3s/releases/download/${VERSION//+/%2B}"
curl -sSfL "${BASE}/k3s" -o "${TMP}/k3s"
curl -sSfL "${BASE}/k3s-airgap-images-${ARCH}.tar.zst" -o "${TMP}/k3s-airgap-images-${ARCH}.tar.zst"
curl -sSfL "${BASE}/sha256sum-${ARCH}.txt" -o "${TMP}/sha256sum.txt"
curl -sSfL https://get.k3s.io -o "${TMP}/install.sh"

echo "[+] Verifying checksums"
(cd "${TMP}" && grep -E " (k3s|k3s-airgap-images-${ARCH}\.tar\.zst)$" sha256sum.txt | sha256sum -c -)

echo "${VERSION}" > "${TMP}/version"
mkdir -p "$(dirname "${CACHE_DIR}")"
rm -rf "${CACHE_DIR}"
mv "${TMP}" "${CACHE_DIR}"
echo "[+] K3s ${VERSION} cached in ${CACHE_DIR}"
