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

# The type is carried into the ISO file name, so that the images of one day
# do not overwrite each other in the release of that day.
ISO_TYPE="$(basename "$CONFIG_FILE")"
ISO_TYPE="${ISO_TYPE%.config}"
export ISO_TYPE

echo "=== Rendering kickstart from $CONFIG_FILE (type: $ISO_TYPE) ==="
python3 lib/render-ks.py --config "$CONFIG_FILE"

exec bash scripts/build-iso.sh "$@"
