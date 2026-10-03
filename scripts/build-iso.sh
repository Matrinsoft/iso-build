#!/bin/bash
# Build a Lingmo OS live ISO from self-built + Fedora packages.
# Entry points: ./build-iso.sh (repo root, renders the kickstart first)
# or "make iso". Requires root (livecd-creator mounts loop devices/chroots).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ORG="${GITHUB_ORG:-Matrinsoft}"
ISO_NAME="lingmoOS_5_Unstable_$(date +%y%m%d)_amd64"
REPO_DIR="${REPO_DIR:-/var/cache/lingmo-repo}"
WORK_DIR="$ROOT"

export GITHUB_ORG="$ORG"
export REPO_DIR
bash "$ROOT/scripts/fetch-rpms.sh"

echo "=== Building live ISO ==="
# Fedora 45 / RPM 6.0: %_pkgverify_level defaults to "all" (valid signature
# AND digest required at RPM transaction level). Workaround:
# https://fedoraproject.org/wiki/Changes/Enforcing_signature_checking_by_default
mkdir -p /etc/rpm
echo '%_pkgverify_level digest' > /etc/rpm/macros.verify
echo "rpm pkgverify_level: $(rpm --eval '%_pkgverify_level')"
# Point the kickstart's lingmo repo at the freshly built local repo
sed -i "s|repo --name=lingmo --baseurl=.*|repo --name=lingmo --baseurl=file://$REPO_DIR --cost=1|" "$ROOT/lingmo-live.ks"

# Self-built rpms are unsigned; make livecd-creator's imgcreate dnf backend
# accept them (nocrypto tsflag + gpgcheck=0).
python3 "$ROOT/lib/patch-imgcreate.py"

livecd-creator \
  --config="$ROOT/lingmo-live.ks" \
  --fslabel="${ISO_NAME}" \
  --title="Lingmo OS 5 (Unstable)" \
  --cache=/tmp/lmc-cache \
  --verbose

# Rename the produced ISO to the canonical name
ISO_OUT="$ROOT/${ISO_NAME}.iso"
if [ -f "/tmp/lingmo_${ISO_NAME}.iso" ] || compgen -G "*.iso" >/dev/null; then
  # livecd-creator writes ISO to current dir with a generated name; find and rename
  produced=$(ls -t *.iso 2>/dev/null | head -1 || true)
  if [ -z "$produced" ]; then
    produced=$(find / -maxdepth 3 -name '*.iso' -newer "$WORK_DIR/repos.txt" 2>/dev/null | head -1)
  fi
  if [ -n "$produced" ]; then
    # livecd-creator may already have written the ISO with the canonical
    # name; mv to the same file fails under set -e
    if [ "$(readlink -f "$produced")" != "$(readlink -f "$ISO_OUT")" ]; then
      mv "$produced" "$ISO_OUT"
    fi
    echo "ISO written to $ISO_OUT"
  fi
fi

if [ ! -f "$ISO_OUT" ]; then
  echo "ERROR: produced ISO not found at $ISO_OUT" >&2
  exit 1
fi
ls -la "$ISO_OUT"

# Gate: verify the boot payload before BUILD_DONE.
python3 "$ROOT/boot/verify-iso.py" "$ISO_OUT"

echo "BUILD_DONE"
