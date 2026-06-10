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
  → K3s single node
    ├── infra/ (traefik, etc)
    └── services/     (jellyfin, sonarr, home assistant, ...)
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
ARGOCD_ADMIN_PASSWORD='your-secret' make bootstrap
```

This installs K3s and ArgoCD.

To also make the API reachable from other machines (e.g. your Mac over
Tailscale) and export a ready-to-use kubeconfig, set `TLS_SANS` (space-separated;
the first entry is used in the exported kubeconfig):

```sh
ARGOCD_ADMIN_PASSWORD='your-secret' \
  TLS_SANS='homelab.tailXXXX.ts.net 100.x.y.z' make bootstrap
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

Two host mounts, shared across all services via `hostPath`:

| Path | Purpose |
|------|---------|
| `/mnt/media` | Media files (tv, movies, downloads) |
| `/mnt/infra-data/<service>` | Service configs (jellyfin, sonarr, etc.) |

K3s pods mount the same directories Docker used — no data migration needed.

## DNS

All services use `*.home.arpa` hostnames (RFC 8375). Configure resolution via:
- AdGuard: wildcard `*.home.arpa → SERVER_IP`
- Or per-device `/etc/hosts`

## Teardown

Removes K3s and all cluster state. Service data on `/mnt/infra-data` and `/mnt/media` is **not** touched.

```sh
make teardown
```

