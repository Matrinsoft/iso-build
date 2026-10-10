#!/bin/bash
# Build a Lingmo OS live ISO from self-built + Fedora packages.
# Entry points: ./build-iso.sh (repo root, renders the kickstart first)
# or "make iso". Requires root (livecd-creator mounts loop devices/chroots).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ORG="${GITHUB_ORG:-Matrinsoft}"
ISO_TYPE="${ISO_TYPE:-desktop}"
ISO_STEM="lingmoOS_5_Unstable"
ISO_DATE="$(date +%y%m%d)"
# The file name carries the ISO type so that the desktop and installer images
# of one day do not collide; the *volume label* has to stay within the 32
# character CD label limit enforced by livecd-creator.
ISO_NAME="${ISO_STEM}_${ISO_TYPE}_${ISO_DATE}_amd64"
ISO_LABEL="${ISO_STEM}_${ISO_DATE}"
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

# The self-built packages are a snapshot of the Fedora sources and are often
# *older* than what Fedora 45 ships today (e.g. gnome-shell 51~rc vs 51.0), and
# a repository's --cost only breaks ties between equal versions - it does not
# override the version comparison. To actually use a self-built package,
# hide its Fedora counterpart from the two Fedora repositories.
#
# Only the packages whose *source* package is listed in FORCE_SELF_BUILT_PKGS
# are forced; everything else stays on Fedora's current packages (forcing the
# whole snapshot also pushed systemd/glib2 back to old pre-releases, which did
# not boot).
FORCE_SELF_BUILT_PKGS="${FORCE_SELF_BUILT_PKGS:-gnome-shell,gnome-control-center,mutter}"
if [ "${FORCE_SELF_BUILT:-1}" = "1" ] && [ -n "$FORCE_SELF_BUILT_PKGS" ]; then
  patterns=$(printf '%s' "$FORCE_SELF_BUILT_PKGS" | tr ',' '|')
  # %{SOURCERPM} of every local rpm -> the source package it was built from;
  # "name-<digit>" avoids matching e.g. gnome-shell-extensions for gnome-shell.
  force_list=$(find "$REPO_DIR" -maxdepth 1 -name '*.rpm' -print0 2>/dev/null \
    | xargs -0 -r rpm -qp --qf '%{SOURCERPM}\t%{NAME}\n' 2>/dev/null \
    | awk -F'\t' -v pat="$patterns" '$1 ~ "^(" pat ")-[0-9]" { print $2 }' \
    | sort -u | paste -sd, -)

  if [ -n "${FORCE_SELF_BUILT_SKIP:-}" ]; then
    # Escape hatch: let Fedora win for the listed packages, e.g. when a Fedora
    # package needs a newer version than the snapshot provides.
    force_list=$(printf '%s' "$force_list" | tr ',' '\n' \
      | grep -vxF -f <(printf '%s' "$FORCE_SELF_BUILT_SKIP" | tr ',' '\n') \
      | paste -sd, -)
  fi

  if [ -n "$force_list" ]; then
    echo "=== Forcing self-built packages over Fedora's: $force_list"
    sed -i -E "s|^(repo --name=fedora[^ ]* .*)$|\1 --excludepkgs=$force_list|" "$ROOT/lingmo-live.ks"
  else
    echo "WARNING: none of '$FORCE_SELF_BUILT_PKGS' found in $REPO_DIR, nothing to force" >&2
  fi
else
  echo "=== Not forcing self-built packages (FORCE_SELF_BUILT=$FORCE_SELF_BUILT, list='$FORCE_SELF_BUILT_PKGS')"
fi

# Self-built rpms are unsigned; make livecd-creator's imgcreate dnf backend
# accept them (nocrypto tsflag + gpgcheck=0).
python3 "$ROOT/lib/patch-imgcreate.py"

livecd-creator \
  --config="$ROOT/lingmo-live.ks" \
  --fslabel="${ISO_LABEL}" \
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
