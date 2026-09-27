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

# Self-built rpms are unsigned; Fedora 45 branched key may be missing in the
# build container. livecd-creator's imgcreate writes its own dnf.conf (which
# does not read the global dnf.conf), so patch its dnf backend to disable
# gpgcheck directly. The signature check lives in dnf.base._sig_check_pkg(),
# which reads each repo's `gpgcheck` attribute; the per-repo value must be
# forced off directly on the repo objects.
python3 - <<'PYEOF'
import glob
f = glob.glob("/usr/lib/python*/site-packages/imgcreate/dnfinst.py")
assert f, "imgcreate dnfinst.py not found"
f = f[0]
s = open(f).read()

# 1) Disable gpgcheck for any cmdline/fallback paths via [main] dnf.conf.
needle_main = 'conf += "tsflags=nocontexts\\n"'
patch_main = 'conf += "tsflags=nocontexts\\n"\n        conf += "gpgcheck=0\\n"\n        conf += "repo_gpgcheck=0\\n"'
if needle_main in s and "gpgcheck=0" not in s:
    s = s.replace(needle_main, patch_main)

# 2) Force gpgcheck off on every repo object right after it is created.
needle_repo = '        repo.enable()\n        repo.set_progress_bar(DownloadProgress())\n'
patch_repo = ('        repo.gpgcheck = False\n'
              '        repo.repo_gpgcheck = False\n'
              '        repo.enable()\n'
              '        repo.set_progress_bar(DownloadProgress())\n')
if needle_repo in s:
    s = s.replace(needle_repo, patch_repo)

open(f, "w").write(s)
print("patched gpgcheck=0 into", f)
PYEOF

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
