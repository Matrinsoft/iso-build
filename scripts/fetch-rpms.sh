#!/bin/bash
# Download the self-built RPMs listed in repos.txt and build the local
# yum repository consumed by the kickstart's "lingmo" repo line.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ORG="${GITHUB_ORG:-Matrinsoft}"
TOKEN="${GITHUB_TOKEN:-}"
REPO_DIR="${REPO_DIR:-/tmp/lingmo-repo}"
WORK_DIR="$ROOT"
curl_auth=()
if [ -n "$TOKEN" ]; then
  curl_auth=(-H "Authorization: Bearer $TOKEN")
fi

echo "=== Downloading self-built RPMs ==="
rm -rf "$REPO_DIR"
mkdir -p "$REPO_DIR"

count=0
while IFS= read -r repo; do
  [ -z "$repo" ] && continue
  echo "  -> $repo"
  # List release .rpm assets (exclude debuginfo to save space/time).
  # Transient TLS failures against GitHub must not abort the build:
  # retry, then treat an empty listing as "nothing to download here".
  api_json=$(curl -sS --retry 5 --retry-all-errors --retry-delay 2 \
    "${curl_auth[@]}" \
    "https://api.github.com/repos/$ORG/$repo/releases/latest" || true)
  urls=$(printf '%s' "$api_json" \
    | python3 -c 'import sys,json
try:
    d=json.load(sys.stdin)
    for a in d.get("assets", []):
        n=a["name"]
        # only fc45 (or noarch) non-debug rpms; older builds may leave fc44/fc46 behind
        if n.endswith(".rpm") and "debuginfo" not in n and "debugsource" not in n and (".fc45." in n or n.endswith(".noarch.rpm")):
            print(a["browser_download_url"])
except Exception as e:
    pass' || true)
  if [ -z "$urls" ]; then
    echo "WARNING: no rpm assets listed for $repo (network error or no release), skipping"
  fi
  for url in $urls; do
    fname="$(basename "$url")"
    curl -fsSL --retry 5 --retry-all-errors --retry-delay 3 \
      "${curl_auth[@]}" -o "$REPO_DIR/$fname" "$url" || {
      echo "WARNING: failed to download $fname, skipping"; rm -f "$REPO_DIR/$fname"; continue; }
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
