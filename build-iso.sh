#!/bin/bash
# Build a Lingmo OS live ISO from self-built + Fedora packages.
set -euo pipefail

ORG="Matrinsoft"
TOKEN="${GITHUB_TOKEN:-}"
ISO_NAME="lingmoOS_5_Unstable_$(date +%y%m%d)_amd64"
REPO_DIR="/tmp/lingmo-repo"
WORK_DIR="$(pwd)"

echo "=== Downloading self-built RPMs ==="
rm -rf "$REPO_DIR"
mkdir -p "$REPO_DIR"

count=0
while IFS= read -r repo; do
  [ -z "$repo" ] && continue
  echo "  -> $repo"
  # List release .rpm assets (exclude debuginfo to save space/time)
  urls=$(curl -sS -H "Authorization: Bearer $TOKEN" \
    "https://api.github.com/repos/$ORG/$repo/releases/latest" \
    | python3 -c 'import sys,json
try:
    d=json.load(sys.stdin)
    for a in d.get("assets", []):
        n=a["name"]
        # only fc45 (or noarch) non-debug rpms; older builds may leave fc44/fc46 behind
        if n.endswith(".rpm") and "debuginfo" not in n and "debugsource" not in n and (".fc45." in n or n.endswith(".noarch.rpm")):
            print(a["browser_download_url"])
except Exception as e:
    pass')
  for url in $urls; do
    fname="$(basename "$url")"
    curl -fsSL --retry 3 --retry-delay 2 -H "Authorization: Bearer $TOKEN" -o "$REPO_DIR/$fname" "$url" || {
      echo "WARNING: failed to download $fname, skipping"; continue; }
    # verify rpm is intact; drop corrupt/incomplete downloads
    if ! rpm -K --nosignature "$REPO_DIR/$fname" >/dev/null 2>&1; then
      echo "WARNING: invalid rpm $fname, removing"; rm -f "$REPO_DIR/$fname"; continue
    fi
    count=$((count+1))
  done
done < "$WORK_DIR/repos.txt"

echo "Downloaded $count RPMs into $REPO_DIR"

echo "=== Creating local repository ==="
createrepo_c "$REPO_DIR"

echo "=== Building live ISO ==="
# Point the kickstart's lingmo repo at the freshly built local repo
sed -i "s|repo --name=lingmo --baseurl=.*|repo --name=lingmo --baseurl=file://$REPO_DIR --cost=1|" "$WORK_DIR/lingmo-live.ks"

livecd-creator \
  --config="$WORK_DIR/lingmo-live.ks" \
  --fslabel="${ISO_NAME}" \
  --title="Lingmo OS 5 (Unstable)" \
  --cache=/tmp/lmc-cache \
  --verbose

# Rename the produced ISO to the canonical name
ISO_OUT="$(pwd)/${ISO_NAME}.iso"
if [ -f "/tmp/lingmo_${ISO_NAME}.iso" ] || compgen -G "*.iso" >/dev/null; then
  # livecd-creator writes ISO to current dir with a generated name; find and rename
  produced=$(ls -t *.iso 2>/dev/null | head -1 || true)
  if [ -z "$produced" ]; then
    produced=$(find / -maxdepth 3 -name '*.iso' -newer "$WORK_DIR/repos.txt" 2>/dev/null | head -1)
  fi
  if [ -n "$produced" ]; then
    mv "$produced" "$ISO_OUT"
    echo "ISO written to $ISO_OUT"
  fi
fi

ls -la "$ISO_OUT" 2>/dev/null || echo "WARNING: could not locate produced ISO"
echo "BUILD_DONE"
