#!/usr/bin/env sh
set -eu

# Historical helper for the old Docker FileBrowser setup.
# Run this on the node where these Longhorn volumes are attached.
# It creates stable host bind paths without hard-coding generated PV names.

volume_for_claim() {
  namespace="$1"
  claim="$2"

  kubectl -n "$namespace" get pvc "$claim" -o jsonpath='{.spec.volumeName}'
}

mount_volume() {
  volume="$1"
  target="$2"

  source="$(findmnt -rn -S "/dev/longhorn/${volume}" -o TARGET | head -n 1)"
  if [ -z "$source" ]; then
    echo "Longhorn volume ${volume} is not mounted on this node" >&2
    exit 1
  fi

  mkdir -p "$target"
  if findmnt -rn "$target" >/dev/null 2>&1; then
    echo "${target} is already mounted"
    return
  fi

  mount --bind "$source" "$target"
  echo "Mounted ${source} -> ${target}"
}

mount_claim() {
  namespace="$1"
  claim="$2"
  target="$3"

  volume="$(volume_for_claim "$namespace" "$claim")"
  if [ -z "$volume" ]; then
    echo "PVC ${namespace}/${claim} is not bound to a volume" >&2
    exit 1
  fi

  mount_volume "$volume" "$target"
}

mount_claim "audiobookshelf" "audiobookshelf-main-library" "/mnt/homelab/audiobookshelf/library"
mount_claim "calibre-web" "calibre-web-books" "/mnt/homelab/calibre-web/library"
mount_claim "calibre-web" "calibre-web-ingest" "/mnt/homelab/calibre-web/ingest"
