# Homelab IaC

Infrastructure-as-code for a homelab built around:

- `k3s` for the Kubernetes cluster
- `Argo CD` for GitOps deployment
- `Tailscale` for secure remote access

## Architecture

```
Work machine: edit + git push
  → Git repo
  → ArgoCD (watches repo, syncs to cluster)
  → K3s 2-node cluster
    ├── infra node: lightweight controllers and ingress
    └── media-worker node: media services
```

## Repo Structure

```
bootstrap/
  bootstrap.sh       One-time K3s + ArgoCD install (run on server)
  teardown.sh        Clean uninstall (keeps service data)
argocd/
  TBD
infra/               Helm charts for infra (traefik, etc)
services/            Helm charts for services (jellyfin, sonarr, etc.)
Makefile             bootstrap / teardown / validate
```

## Quick Start

### 1. Bootstrap (on the server)

```sh
git clone https://github.com/huynhtt8/homelab && cd homelab
K3S_ROLE=server \
K3S_NODE_NAME=k3s-master-01 \
K3S_NODE_IP=<server-tailnet-ip> \
K3S_NODE_EXTERNAL_IP=<server-tailnet-ip> \
TLS_SANS='<server-tailnet-ip> k3s-master-01 <server-name>.your-tailnet.ts.net' \
ARGOCD_ADMIN_PASSWORD='your-secret' \
make bootstrap
```

This installs K3s and ArgoCD.

To also make the API reachable from other machines (e.g. your Mac over
Tailscale) and export a ready-to-use kubeconfig, set `TLS_SANS` (space-separated;
the first entry is used in the exported kubeconfig). Keep the Tailnet IP and
node names in your shell env, not in Git.

```sh
K3S_ROLE=server \
K3S_NODE_NAME=k3s-master-01 \
K3S_NODE_IP=<server-tailnet-ip> \
K3S_NODE_EXTERNAL_IP=<server-tailnet-ip> \
TLS_SANS='<server-name>.your-tailnet.ts.net <server-tailnet-ip>' \
ARGOCD_ADMIN_PASSWORD='your-secret' \
make bootstrap
```

To join the worker node, run the same script in agent mode:

```sh
K3S_ROLE=agent \
K3S_NODE_NAME=k3s-worker-media-01 \
K3S_NODE_IP=<worker-tailnet-ip> \
K3S_NODE_EXTERNAL_IP=<worker-tailnet-ip> \
K3S_SERVER_URL=https://<server-tailnet-ip>:6443 \
K3S_TOKEN='k3s token from server' \
make bootstrap-worker
```

### 2. Apply root service (one-time)

```sh
kubectl apply -f argocd/root.yaml
```

ArgoCD takes over from here — it reads `argocd/` and deploys everything.

### 3. Day-to-day workflow

```sh
# Edit an service's values
vim services/jellyfin/values.yaml

# Validate locally
make validate

# Push — ArgoCD auto-syncs
git add -A && git commit -m 'chore: update jellyfin' && git push
```

## Adding a New Service

1. Create `services/<name>/Chart.yaml` (use `app-template` v2.6.0)
2. Create `services/<name>/values.yaml` (image, ports, ingress host, hostPath mounts)
3. Create `argocd/services/<name>.yaml` (ArgoCD Application, wave 2)
4. `make validate` → commit → push

## Storage

Node placement:

| Node label | Workloads |
|------|-----------|
| `node-type=infra` | Traefik, cert-manager, External Secrets, and other lightweight controllers |
| `node-type=media-worker` | All services that mount hostPath data (`/mnt/media`, `/mnt/infra-data`, `/mnt/hdd2`) |

Two host mounts, shared across the media services via `hostPath`:

| Path | Purpose |
|------|---------|
| `/mnt/media` | Media files (tv, movies, downloads) |
| `/mnt/infra-data/<service>` | Service configs (jellyfin, sonarr, etc.) |

K3s pods mount the same directories Docker used on the media worker node - no data migration needed.

## DNS

All services use `*.home.arpa` hostnames (RFC 8375). Configure resolution via:
- AdGuard: wildcard `*.home.arpa → SERVER_IP`
- Or per-device `/etc/hosts`

## Teardown

Removes K3s and all cluster state. Service data on `/mnt/infra-data` and `/mnt/media` is **not** touched.

```sh
make teardown
```
