#!/bin/bash
# Download the self-built RPMs listed in repos.txt and build the local
# yum repository consumed by the kickstart's "lingmo" repo line.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ORG="${GITHUB_ORG:-Matrinsoft}"
TOKEN="${GITHUB_TOKEN:-}"
REPO_DIR="${REPO_DIR:-/var/cache/lingmo-repo}"
WORK_DIR="$ROOT"
DOWNLOAD_JOBS="${RPM_DOWNLOAD_JOBS:-6}"
case "$DOWNLOAD_JOBS" in
  ''|*[!0-9]*|0) DOWNLOAD_JOBS=6 ;;
esac
curl_auth=()
if [ -n "$TOKEN" ]; then
  curl_auth=(-H "Authorization: Bearer $TOKEN")
fi

echo "=== Downloading self-built RPMs ==="
mkdir -p "$REPO_DIR"

urls_file="$(mktemp)"
api_cache="$REPO_DIR/.api-cache"
mkdir -p "$api_cache"
trap 'rm -f "$urls_file" "$urls_file".*' EXIT

while IFS= read -r repo; do
  [ -z "$repo" ] && continue
  echo "  -> $repo"
  # List release .rpm assets (exclude debuginfo to save space/time).
  # Transient TLS failures against GitHub must not abort the build:
  # retry, then treat an empty listing as "nothing to download here".
  api_file="$api_cache/$repo.json"
  api_tmp="$api_file.part.$$"
  if curl -fsS --connect-timeout 8 --max-time 30 \
      --retry 3 --retry-all-errors --retry-delay 2 \
      "${curl_auth[@]}" \
      -o "$api_tmp" \
      "https://api.github.com/repos/$ORG/$repo/releases/latest" \
      && python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$api_tmp"; then
    mv -f "$api_tmp" "$api_file"
  else
    rm -f "$api_tmp"
  fi
  if [ -s "$api_file" ]; then
    api_json="$(cat "$api_file")"
  else
    api_json=""
  fi
  urls=$(printf '%s' "$api_json" \
    | python3 -c 'import sys,json
try:
    d=json.load(sys.stdin)
    for a in d.get("assets", []):
        n=a["name"]
        # only fc45 (or noarch) non-debug rpms; older builds may leave fc44/fc46 behind
        if n.endswith(".rpm") and not n.endswith(".src.rpm") and "debuginfo" not in n and "debugsource" not in n and (".fc45." in n or n.endswith(".noarch.rpm")):
            print(a["browser_download_url"])
except Exception as e:
    pass' || true)
  if [ -z "$urls" ]; then
    echo "WARNING: no rpm assets listed for $repo (network error or no release), skipping"
  fi
  while IFS= read -r url; do
    [ -z "$url" ] || printf '%s\t%s\n' "$(basename "$url")" "$url" >> "$urls_file"
  done <<< "$urls"
done < "$WORK_DIR/repos.txt"

download_one() {
  local fname="$1" url="$2" target="$REPO_DIR/$1" temp="$REPO_DIR/$1.part.$$"
  if [ -f "$target" ] && rpm -K --nosignature "$target" >/dev/null 2>&1; then
    echo "  cached: $fname"
    return 0
  fi
  rm -f "$target" "$temp"
  if ! curl -fsSL --retry 5 --retry-all-errors --retry-delay 3 \
      "${curl_auth[@]}" -o "$temp" "$url"; then
    echo "WARNING: failed to download $fname, skipping" >&2
    rm -f "$temp"
    return 0
  fi
  if ! rpm -K --nosignature "$temp" >/dev/null 2>&1; then
    echo "WARNING: invalid rpm $fname, removing" >&2
    rm -f "$temp"
    return 0
  fi
  mv -f "$temp" "$target"
}

export REPO_DIR

echo "=== Downloading RPM assets ($DOWNLOAD_JOBS parallel jobs) ==="
while IFS=$'\t' read -r fname url; do
  [ -z "$fname" ] && continue
  while [ "$(jobs -rp | wc -l)" -ge "$DOWNLOAD_JOBS" ]; do
    wait -n || true
  done
  download_one "$fname" "$url" &
done < "$urls_file"
wait

count=0
for rpm in "$REPO_DIR"/*.rpm; do
  [ -f "$rpm" ] || continue
  if rpm -K --nosignature "$rpm" >/dev/null 2>&1; then
    count=$((count + 1))
  fi
done
echo "Downloaded or reused $count RPMs in $REPO_DIR"

echo "=== Creating local repository ==="
createrepo_c "$REPO_DIR"
