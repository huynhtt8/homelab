#!/bin/bash
set -euo pipefail

# --- Teardown K3s ---
# This completely removes K3s and all cluster data.
# Your app data on /mnt/infra-data and /mnt/media is NOT touched.
# Usage: bash bootstrap/teardown.sh

echo "This will COMPLETELY remove K3s and all cluster state."
echo "App data on /mnt/infra-data and /mnt/media will NOT be deleted."
read -p "Continue? [y/N] " confirm
[[ "${confirm}" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

if [ -f /usr/local/bin/k3s-uninstall.sh ]; then
  echo "=== Uninstalling K3s ==="
  /usr/local/bin/k3s-uninstall.sh
  echo "K3s removed."
else
  echo "K3s uninstall script not found — already removed?"
fi
