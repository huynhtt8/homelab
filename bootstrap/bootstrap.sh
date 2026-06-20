#!/bin/bash
set -euo pipefail

# --- K3s + ArgoCD Bootstrap ---
# Run this on either the control-plane node or a worker node.
# Usage: bash bootstrap/bootstrap.sh

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root. Use: sudo -E make bootstrap" >&2
  exit 1
fi

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
K3S_VERSION="${K3S_VERSION:-v1.33.12+k3s1}"
ARGOCD_NODEPORT="${ARGOCD_NODEPORT:-30443}"
ARGOCD_ADMIN_PASSWORD="${ARGOCD_ADMIN_PASSWORD:-}"
K3S_ROLE="${K3S_ROLE:-server}"
K3S_NODE_NAME="${K3S_NODE_NAME:-$(hostname)}"
K3S_NODE_IP="${K3S_NODE_IP:-}"
K3S_NODE_EXTERNAL_IP="${K3S_NODE_EXTERNAL_IP:-${K3S_NODE_IP}}"
K3S_SERVER_URL="${K3S_SERVER_URL:-}"
K3S_TOKEN="${K3S_TOKEN:-}"
K3S_FLANNEL_EXTERNAL_IP="${K3S_FLANNEL_EXTERNAL_IP:-true}"
K3S_DISABLE="${K3S_DISABLE:-traefik,servicelb}"
K3S_WRITE_KUBECONFIG_MODE="${K3S_WRITE_KUBECONFIG_MODE:-0644}"
# Extra addresses (Tailscale IP / MagicDNS name) remote clients use to reach the
# API server. Space-separated; the first is also used in the exported kubeconfig.
TLS_SANS="${TLS_SANS:-}"

if [ "${K3S_ROLE}" != "server" ] && [ "${K3S_ROLE}" != "agent" ]; then
  echo "K3S_ROLE must be 'server' or 'agent'." >&2
  exit 1
fi

if [ -z "${K3S_NODE_IP}" ]; then
  echo "K3S_NODE_IP is required." >&2
  exit 1
fi

if [ "${K3S_ROLE}" = "agent" ]; then
  : "${K3S_SERVER_URL:?Set K3S_SERVER_URL for agent bootstrap}"
  : "${K3S_TOKEN:?Set K3S_TOKEN for agent bootstrap}"
fi

K3S_CONFIG="/etc/rancher/k3s/config.yaml"
mkdir -p /etc/rancher/k3s
chmod 700 /etc/rancher/k3s

{
  echo "node-name: ${K3S_NODE_NAME}"
  echo "node-ip: ${K3S_NODE_IP}"
  echo "node-external-ip: ${K3S_NODE_EXTERNAL_IP}"
  echo "write-kubeconfig-mode: \"${K3S_WRITE_KUBECONFIG_MODE}\""
  if [ "${K3S_ROLE}" = "server" ]; then
    echo "disable:"
    IFS=',' read -ra DISABLED_COMPONENTS <<< "${K3S_DISABLE}"
    for component in "${DISABLED_COMPONENTS[@]}"; do
      echo "  - ${component}"
    done
    echo "flannel-external-ip: ${K3S_FLANNEL_EXTERNAL_IP}"
    if [ -n "${TLS_SANS}" ]; then
      echo "tls-san:"
      for san in ${TLS_SANS}; do
        echo "  - ${san}"
      done
    fi
  fi
  if [ "${K3S_ROLE}" = "agent" ]; then
    echo "server: ${K3S_SERVER_URL}"
    echo "token: ${K3S_TOKEN}"
  fi
} > "${K3S_CONFIG}"
chmod 600 "${K3S_CONFIG}"

echo "=== Installing K3s ${K3S_VERSION} (${K3S_ROLE}) ==="
INSTALL_K3S_EXEC="${K3S_ROLE}"
if [ "${K3S_ROLE}" = "server" ]; then
  INSTALL_K3S_EXEC="${INSTALL_K3S_EXEC} --secrets-encryption"
fi
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="${K3S_VERSION}" INSTALL_K3S_EXEC="${INSTALL_K3S_EXEC}" sh -s -

if [ "${K3S_ROLE}" = "server" ]; then
  echo "=== Waiting for K3s to be ready ==="
  # K3s needs a few seconds to register the node
  for i in $(seq 1 30); do
    kubectl get nodes &>/dev/null && break
    echo "  waiting for node to register... (${i}/30)"
    sleep 2
  done
  kubectl wait --for=condition=Ready node --all --timeout=120s

  echo "=== Labeling local node as infra ==="
  kubectl label node "${K3S_NODE_NAME}" node-type=infra --overwrite

  echo "=== Installing Helm (if needed) ==="
  if ! command -v helm &>/dev/null; then
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  fi

  if [ -z "${ARGOCD_ADMIN_PASSWORD}" ]; then
    echo "ARGOCD_ADMIN_PASSWORD is required for server bootstrap." >&2
    exit 1
  fi

  if ! command -v htpasswd &>/dev/null; then
    apt-get update
    apt-get install -y apache2-utils
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
  echo "ArgoCD UI:  http://$(hostname -I | awk '{print $1}'):30080"
  echo "Username:   admin"
  echo "Password:   (the ARGOCD_ADMIN_PASSWORD you provided)"
  if [ -n "${TLS_SANS}" ]; then
    echo ""
    echo "Remote kubeconfig: ${KUBECONFIG_OUT} (contains credentials — don't commit)"
    echo "  From your Mac:  scp $(whoami)@${PRIMARY_SAN}:${KUBECONFIG_OUT} ~/.kube/homelab.yaml"
  fi
  echo ""
  echo "Next: label the media node with node-type=media-worker, then apply your root app"
  echo "  kubectl label node <media-node-name> node-type=media-worker --overwrite"
  echo "  kubectl apply -f argocd/root.yaml"
else
  echo ""
  echo "=== Done! ==="
  echo "Worker node: ${K3S_NODE_NAME}"
  echo "Join target:  ${K3S_SERVER_URL}"
  echo "Next: label this node as media-worker from the control-plane"
  echo "  kubectl label node ${K3S_NODE_NAME} node-type=media-worker --overwrite"
fi
