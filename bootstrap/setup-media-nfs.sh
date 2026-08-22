#!/usr/bin/env bash
set -euo pipefail

MEDIA_ROOT="${MEDIA_ROOT:-/mnt/media}"
NFS_ALLOWED_CIDR="${NFS_ALLOWED_CIDR:-192.168.1.0/24}"
EXPORTS_FILE="${EXPORTS_FILE:-/etc/exports.d/homelab-media.exports}"
MEDIA_UID="${MEDIA_UID:-1000}"
MEDIA_GID="${MEDIA_GID:-1000}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root on the media-worker node that owns ${MEDIA_ROOT}." >&2
  exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
  echo "This helper expects a Debian/Ubuntu node with apt-get." >&2
  exit 1
fi

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y nfs-kernel-server

install -d -o "${MEDIA_UID}" -g "${MEDIA_GID}" "${MEDIA_ROOT}"
install -d -o "${MEDIA_UID}" -g "${MEDIA_GID}" \
  "${MEDIA_ROOT}/movies" \
  "${MEDIA_ROOT}/tv" \
  "${MEDIA_ROOT}/downloads" \
  "${MEDIA_ROOT}/downloads/incomplete" \
  "${MEDIA_ROOT}/downloads/radarr" \
  "${MEDIA_ROOT}/downloads/sonarr" \
  "${MEDIA_ROOT}/music" \
  "${MEDIA_ROOT}/books" \
  "${MEDIA_ROOT}/books/audiobookshelf" \
  "${MEDIA_ROOT}/books/calibre-library" \
  "${MEDIA_ROOT}/books/calibre-ingest"

install -d -m 0755 /etc/exports.d
cat > "${EXPORTS_FILE}" <<EOF
${MEDIA_ROOT} ${NFS_ALLOWED_CIDR}(rw,sync,no_subtree_check,fsid=1,all_squash,anonuid=${MEDIA_UID},anongid=${MEDIA_GID})
EOF

exportfs -ra
if systemctl list-unit-files nfs-server.service >/dev/null 2>&1; then
  systemctl enable --now nfs-server
else
  systemctl enable --now nfs-kernel-server
fi

echo "Exported ${MEDIA_ROOT} to ${NFS_ALLOWED_CIDR}"
