# Worker Docker Services

Node-local services that must run outside K3s on
`root@<worker-tailnet-host>`.

These containers are not managed by ArgoCD. Keep secrets in the remote `.env`
file only; do not commit it.

## Services

| Service | URL | Purpose |
|---------|-----|---------|
| AdGuard Home | `http://<worker-tailnet-host>:82` | LAN and tailnet DNS |

## LAN DNS

AdGuard Home runs on the worker's LAN IP, `<worker-lan-ip>`, and has a
DNS rewrite for:

```text
*.homelab.com -> <worker-lan-ip>
```

To use homelab hostnames on LAN clients without Tailscale, configure the router
DHCP DNS server to `<worker-lan-ip>`, or set that DNS server manually per device.

## FileBrowser

FileBrowser now runs in K3s as `services/filebrowser` and mounts the
media-worker NFS export directly. Do not deploy a Docker FileBrowser compose
stack on the worker.

The old helper that bind-mounted Longhorn `pvc-...` devices is kept only as
historical reference and should not be used for new cluster builds.

Before syncing the K3s FileBrowser app, configure the media-worker NFS export:

```sh
ssh root@<worker-tailnet-host> 'cd /opt/homelab && make setup-media-nfs'
```

## Deploy

```sh
scp -r docker/worker/adguardhome root@<worker-tailnet-host>:/opt/homelab-docker/worker/
```

AdGuard state is stored under
`/opt/homelab-docker/worker/adguardhome/adguardhome/{conf,work}` on the worker.
If this directory is lost, restore it from the NAS copy at
`root@<nas-tailnet-host>:/home/nas/apps/adguardhome/adguardhome/` before
restarting the AdGuard container.

After the AdGuard data directories are restored, manage it separately:

```sh
ssh root@<worker-tailnet-host> 'cd /opt/homelab-docker/worker/adguardhome && docker compose up -d'
```
