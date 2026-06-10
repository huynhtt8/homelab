#!/bin/bash
set -euo pipefail

# --- K3s + ArgoCD Bootstrap ---
# Run this ON the Ubuntu server. One-time setup.
# Usage: bash bootstrap/bootstrap.sh

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
K3S_VERSION="${K3S_VERSION:-v1.33.12+k3s1}"
ARGOCD_NODEPORT="${ARGOCD_NODEPORT:-30443}"
ARGOCD_ADMIN_PASSWORD="${ARGOCD_ADMIN_PASSWORD:?Set ARGOCD_ADMIN_PASSWORD before running (plaintext, will be hashed)}"
# Extra addresses (Tailscale IP / MagicDNS name) remote clients use to reach the
# API server. Space-separated; the first is also used in the exported kubeconfig.
TLS_SANS="${TLS_SANS:-}"

echo "=== Installing K3s ${K3S_VERSION} ==="
# Add any TLS_SANS as --tls-san flags so the API cert is valid for remote
# addresses (e.g. Tailscale) from first boot.
SAN_ARGS=()
for san in ${TLS_SANS}; do SAN_ARGS+=(--tls-san "$san"); done
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="${K3S_VERSION}" sh -s - \
  --write-kubeconfig-mode 0644 \
  --disable traefik \
  --secrets-encryption \
  ${SAN_ARGS[@]+"${SAN_ARGS[@]}"}

echo "=== Waiting for K3s to be ready ==="
# K3s needs a few seconds to register the node
for i in $(seq 1 30); do
  kubectl get nodes &>/dev/null && break
  echo "  waiting for node to register... (${i}/30)"
  sleep 2
done
kubectl wait --for=condition=Ready node --all --timeout=120s

echo "=== Installing Helm (if needed) ==="
if ! command -v helm &>/dev/null; then
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

echo "=== Hashing ArgoCD admin password ==="
ARGOCD_HASH=$(htpasswd -nbBC 10 "" "${ARGOCD_ADMIN_PASSWORD}" | cut -d: -f2)

echo "=== Installing ArgoCD via Helm ==="
helm repo add argo https://argoproj.github.io/argo-helm --force-update
helm repo update
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --set server.service.type=NodePort \
  --set server.service.nodePortHttp=30080 \
  --set "server.service.nodePortHttps=${ARGOCD_NODEPORT}" \
  --set configs.params.server\\.insecure=true \
  --set "configs.secret.argocdServerAdminPassword=${ARGOCD_HASH}" \
  --wait \
  --timeout 5m

echo "=== Waiting for ArgoCD server ==="
kubectl wait --for=condition=available deployment/argocd-server \
  --namespace argocd --timeout=120s

echo "=== Exporting kubeconfig ==="
if [ -n "${TLS_SANS}" ]; then
  PRIMARY_SAN="${TLS_SANS%% *}"
  KUBECONFIG_OUT="${HOME}/kubeconfig-homelab.yaml"
  sed "s#https://127.0.0.1:6443#https://${PRIMARY_SAN}:6443#" \
    /etc/rancher/k3s/k3s.yaml > "${KUBECONFIG_OUT}"
  echo "Wrote remote kubeconfig to ${KUBECONFIG_OUT}"
else
  echo "TLS_SANS not set — skipping remote kubeconfig export."
fi

echo ""
echo "=== Done! ==="
echo "ArgoCD UI:  https://$(hostname -I | awk '{print $1}'):${ARGOCD_NODEPORT}"
echo "Username:   admin"
echo "Password:   (the ARGOCD_ADMIN_PASSWORD you provided)"
if [ -n "${TLS_SANS}" ]; then
  echo ""
  echo "Remote kubeconfig: ${KUBECONFIG_OUT} (contains credentials — don't commit)"
  echo "  From your Mac:  scp $(whoami)@${PRIMARY_SAN}:${KUBECONFIG_OUT} ~/.kube/homelab.yaml"
fi
echo ""
echo "Next: apply your root app"
echo "  kubectl apply -f argocd/root.yaml"
