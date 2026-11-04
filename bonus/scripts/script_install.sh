#!/bin/bash

# Stop at the first failing command instead of looping on a broken install
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BONUS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

#____Make Sure P3 is Launch:
if ! kubectl get namespace argocd &>/dev/null; then
    echo "[ERROR] p3 is not installed: run 'make p3-install' first" >&2
    exit 1
fi
kubectl wait --for=condition=available --timeout=60s deployment/argocd-server -n argocd

#___Installation of Helm
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4 | bash
helm version

#___Creation of namespace for Redis and Postresql Installation
# create | apply keeps the script re-runnable when the namespace already exists
kubectl create namespace gitlab --dry-run=client -o yaml | kubectl apply -f -

#__Passwords for PostgreSQL / Redis, read from bonus/.env (not committed)
ENV_FILE="${BONUS_DIR}/.env"
# Fresh clone: no .env yet, create it from .env.example with random passwords
if [ ! -f "${ENV_FILE}" ]; then
    echo "[+] ${ENV_FILE} missing: generating it with random passwords"
    ( umask 077
      sed -e "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$(openssl rand -hex 16)/" \
          -e "s/^REDIS_PASSWORD=.*/REDIS_PASSWORD=$(openssl rand -hex 16)/" \
          "${BONUS_DIR}/.env.example" > "${ENV_FILE}" )
fi
set -a; . "${ENV_FILE}"; set +a
: "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD is empty in ${ENV_FILE}}"
: "${REDIS_PASSWORD:?REDIS_PASSWORD is empty in ${ENV_FILE}}"

# dry-run | apply: re-runnable, updates the secret if it already exists
kubectl -n gitlab create secret generic gitlab-postgresql \
    --from-literal=password="${POSTGRES_PASSWORD}" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n gitlab create secret generic gitlab-redis \
    --from-literal=password="${REDIS_PASSWORD}" --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f "${BONUS_DIR}/confs/gitlab/postgresql.yaml"
kubectl apply -f "${BONUS_DIR}/confs/gitlab/redis.yaml"
for app in gitlab-postgresql gitlab-redis; do
    until kubectl get pod -n gitlab -l app="${app}" -o name | grep -q .; do sleep 2; done
    kubectl wait --for=condition=Ready pod -l app="${app}" -n gitlab --timeout=300s
done


#__Installation of gitlab
helm repo add gitlab https://charts.gitlab.io/
helm repo update
kubectl apply -f "${BONUS_DIR}/confs/gitlab/toolbox-backup-secret.yaml"
helm upgrade --install gitlab gitlab/gitlab -n gitlab --version 10.5.4 --timeout 20m -f "${BONUS_DIR}/confs/gitlab/gitlab-values.yaml"
kubectl apply -f "${BONUS_DIR}/confs/gitlab/gitlab-ingress.yaml"
grep -q "gitlab\.local" /etc/hosts || echo "127.0.0.1 gitlab.local" | sudo tee -a /etc/hosts

echo "[+] Waiting for GitLab (migrations, webservice, login page)"
kubectl wait --for=condition=complete job -l app=migrations -n gitlab --timeout=900s
kubectl wait --for=condition=available deployment/gitlab-webservice-default deployment/gitlab-toolbox -n gitlab --timeout=900s
until [ "$(curl -s -o /dev/null -m 5 -w '%{http_code}' http://gitlab.local/users/sign_in)" = "200" ]; do sleep 5; done

#__Root password
kubectl get secret gitlab-gitlab-initial-root-password -n gitlab -ojsonpath='{.data.password}' | base64 -d > "${BONUS_DIR}/confs/gitlab/Password"
echo "" >> "${BONUS_DIR}/confs/gitlab/Password"

#__API token for root (created inside the toolbox pod; only kept in this shell)
GITLAB_URL="http://gitlab.local"
PROJECT="pjurdana-iot"
TOKEN="iot-$(head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 24)"
kubectl exec -n gitlab deploy/gitlab-toolbox -c toolbox -- gitlab-rails runner "
u = User.find_by_username('root')
t = u.personal_access_tokens.create!(name: 'iot-' + Time.now.to_i.to_s, scopes: [:api], expires_at: 30.days.from_now)
t.set_token('${TOKEN}')
t.save!"

#__Project creation (public, so Argo CD needs no credentials); ignored if it already exists
curl -s -o /dev/null -X POST -H "PRIVATE-TOKEN: ${TOKEN}" \
    -d "name=${PROJECT}&visibility=public" "${GITLAB_URL}/api/v4/projects"

#__Push the app (v1) from a temporary directory, only if the repo is still empty
#  (main is protected: a re-run must not overwrite what was pushed or edited since)
if curl -sf -H "PRIVATE-TOKEN: ${TOKEN}" "${GITLAB_URL}/api/v4/projects/root%2F${PROJECT}/repository/tree?path=deployment" | grep -q deploy.yaml; then
    echo "[+] ${PROJECT} already contains the app, push skipped"
else
    TMP_REPO="$(mktemp -d)"
    mkdir "${TMP_REPO}/deployment"
    cp "${BONUS_DIR}"/confs/app/*.yaml "${TMP_REPO}/deployment/"
    (
        cd "${TMP_REPO}" || exit 1
        git init -q -b main
        git add .
        git -c user.name=root -c user.email=root@gitlab.local commit -q -m "feat: wil42 playground v1"
        git push -q "http://root:${TOKEN}@gitlab.local/root/${PROJECT}.git" main
    )
    rm -rf "${TMP_REPO}"
fi
unset TOKEN

#__Argo CD now syncs from GitLab (same Application name as p3: source replaced in place)
kubectl apply -f "${BONUS_DIR}/confs/argocd/argocd-gitlab.yaml"

#__Force Argo CD to re-read the repository now (otherwise it polls every ~3 min)
kubectl annotate app argocd -n argocd argocd.argoproj.io/refresh=hard --overwrite
echo "[+] Waiting for Argo CD to sync from GitLab"
for _ in $(seq 1 60); do
    STATUS="$(kubectl get app argocd -n argocd -o jsonpath='{.status.sync.status}/{.status.health.status}')"
    [ "${STATUS}" = "Synced/Healthy" ] && break
    sleep 5
done
[ "${STATUS}" = "Synced/Healthy" ] || { echo "[ERROR] Argo CD not synced: ${STATUS}" >&2; exit 1; }

echo "GitLab: ${GITLAB_URL} (root / password in ${BONUS_DIR}/confs/gitlab/Password)"