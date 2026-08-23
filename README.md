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
K3S_NODE_IP=<server-lan-ip> \
K3S_NODE_EXTERNAL_IP=<server-tailnet-ip> \
K3S_FLANNEL_EXTERNAL_IP=false \
TLS_SANS='<server-tailnet-ip> k3s-master-01 <server-name>.your-tailnet.ts.net' \
ARGOCD_ADMIN_PASSWORD='your-secret' \
make bootstrap
```

This installs K3s and ArgoCD.

K3s ServiceLB is left enabled by default. The bootstrap script disables the
bundled K3s Traefik only, while the repo-managed Traefik chart exposes a
`LoadBalancer` service that ServiceLB can advertise on the local network.

To also make the API reachable from other machines (e.g. your Mac over
Tailscale) and export a ready-to-use kubeconfig, set `TLS_SANS` (space-separated;
the first entry is used in the exported kubeconfig). Keep the Tailnet IP and
node names in your shell env, not in Git.

```sh
K3S_ROLE=server \
K3S_NODE_NAME=k3s-master-01 \
K3S_NODE_IP=<server-lan-ip> \
K3S_NODE_EXTERNAL_IP=<server-tailnet-ip> \
K3S_FLANNEL_EXTERNAL_IP=false \
TLS_SANS='<server-name>.your-tailnet.ts.net <server-tailnet-ip>' \
ARGOCD_ADMIN_PASSWORD='your-secret' \
make bootstrap
```

To join the worker node, run the same script in agent mode:

```sh
K3S_ROLE=agent \
K3S_NODE_NAME=k3s-worker-media-01 \
K3S_NODE_IP=<worker-lan-ip> \
K3S_NODE_EXTERNAL_IP=<worker-tailnet-ip> \
K3S_SERVER_URL=https://<server-tailnet-ip>:6443 \
K3S_TOKEN='k3s token from server' \
make bootstrap-worker
```

To reset a standalone Wyse 5070 and join it as a clean agent, first back up
anything still needed from the old node, then run the matching K3s uninstall
script on the Wyse:

```sh
sudo /usr/local/bin/k3s-uninstall.sh
# or, if the node was installed as an agent:
sudo /usr/local/bin/k3s-agent-uninstall.sh
```

Remove stale cluster state only after confirming the old node data is not
needed:

```sh
sudo rm -rf /etc/rancher/k3s /var/lib/rancher/k3s /var/lib/kubelet /var/lib/longhorn
sudo apt-get update
sudo apt-get install -y nfs-common open-iscsi
sudo systemctl enable --now iscsid
```

Join the Wyse with its own node name and private IP:

```sh
K3S_ROLE=agent \
K3S_NODE_NAME=k3s-worker-wyse-5070 \
K3S_NODE_IP=<wyse-lan-ip> \
K3S_NODE_EXTERNAL_IP=<wyse-tailnet-ip> \
K3S_SERVER_URL=https://<server-tailnet-ip>:6443 \
K3S_TOKEN='k3s token from server' \
make bootstrap-worker
```

After it joins, label the nodes:

```sh
kubectl label node k3s-master-01 node-type=infra --overwrite
kubectl label node k3s-master-01 hardware.zigbee=true --overwrite
kubectl label node k3s-master-01 node.longhorn.io/create-default-disk=true --overwrite

kubectl label node k3s-worker-wyse-5070 node-type=infra --overwrite
kubectl label node k3s-worker-wyse-5070 workload-tier=general --overwrite
kubectl label node k3s-worker-wyse-5070 node.longhorn.io/create-default-disk=true --overwrite
```

On the media-worker node, export the shared media root over NFS before syncing
media services:

```sh
sudo make setup-media-nfs
```

Store the real NFS server address in private Pulumi config, not in public Helm
values:

```sh
cd pulumi
pulumi config set --path homelab:runtime.nfsServer '<media-worker-lan-ip-or-private-dns>'
pulumi config set --path homelab:runtime.mediaPath /mnt/media
pulumi up
```

Pulumi creates one `media-share` PVC in each namespace that needs shared media.
Service charts only reference that claim name.

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
2. Create `services/<name>/values.yaml` (image, ports, ingress host, Longhorn PVCs)
3. Create `argocd/services/<name>.yaml` (ArgoCD Application, wave 2)
4. `make validate` → commit → push

## Storage

Node placement:

| Node label | Workloads |
|------|-----------|
| `node-type=infra` | Traefik, cert-manager, External Secrets, and other lightweight controllers |
| `node-type=media-worker` | Media services and the node that exports `/mnt/media` over NFS |

Storage used by the media services:

| Path | Purpose |
|------|---------|
| NFS `/mnt/media` | Combined media pool for tv, movies, downloads, and book libraries |
| Longhorn PVCs | Service configs, app databases, metadata, and app-owned files |

Longhorn defaults new volumes to two replicas. Existing volumes created with one
replica must still be updated in Longhorn after the second storage node is
available, then left to rebuild before relying on node failover.

The two 500GB HDDs are mounted below `/mnt/media-a` and `/mnt/media-b`, then
combined at `/mnt/media` with mergerfs. The media-worker exports `/mnt/media`
over NFS, and Kubernetes workloads mount that export instead of node-local
`hostPath` volumes. This keeps shared media visible when pods run on another
cluster node.

The standard shared layout is:

| Host/NFS path | Container path |
|---------------|----------------|
| `/mnt/media/movies` | `/data/movies` |
| `/mnt/media/tv` | `/data/tv` |
| `/mnt/media/downloads` | `/data/downloads` |
| `/mnt/media/books/audiobookshelf` | `/library` |
| `/mnt/media/books/calibre-library` | `/calibre-library` |
| `/mnt/media/books/calibre-ingest` | `/cwa-book-ingest` |

Copyparty currently uses Longhorn RWO PVCs and should run as a single replica.
For active multi-replica Copyparty across nodes, move the share volume to RWX
storage such as NFS or SMB and mount that claim at `/w`.

## DNS

All services use service-name `*.homelab.com` hostnames (RFC 8375), such as
`sonarr.homelab.com` and `calibre-web.homelab.com`. Configure resolution via:
- AdGuard: wildcard `*.homelab.com → SERVER_IP`
- Or per-device `/etc/hosts`

## Teardown

Removes K3s and all cluster state. Service data on `/mnt/media` is **not** touched.

```sh
make teardown
```
