#!/bin/bash
# Build a Lingmo OS live ISO from self-built + Fedora packages.
# Real implementation lives in scripts/; this root file is the stable entry
# point used by CI (bash build-iso.sh) and by "make iso".
set -euo pipefail
cd "$(dirname "$0")"

# Render lingmo-live.ks from core/ks fragments + .config (defaults produce
# the exact same file a bare checkout already contains, so CI behaviour is
# unchanged).
python3 lib/render-ks.py

exec bash scripts/build-iso.sh "$@"
