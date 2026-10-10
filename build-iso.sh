#!/bin/bash
# Build a Lingmo OS live ISO from self-built + Fedora packages.
# Real implementation lives in scripts/; this root file is the stable entry
# point used by CI (bash build-iso.sh) and by "make iso".
set -euo pipefail
cd "$(dirname "$0")"

# Render lingmo-live.ks from core/ks fragments + the selected configuration.
# $ISO_CONFIG (or the first argument) selects a tracked config file; without
# it the desktop defaults are used, which is what a bare checkout produced
# before the configuration was split.
CONFIG_FILE="${ISO_CONFIG:-${1:-configs/desktop.config}}"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: configuration file not found: $CONFIG_FILE" >&2
  exit 1
fi

echo "=== Rendering kickstart from $CONFIG_FILE ==="
python3 lib/render-ks.py --config "$CONFIG_FILE"

exec bash scripts/build-iso.sh "$@"
