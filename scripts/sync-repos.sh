#!/bin/bash
# Sync every source project described by default.xml using the official
# Android "repo" tool (https://github.com/GerritCodeReview/git-repo).
#
#   WORKSPACE   workspace root holding the checkouts
#               (default: ../gnome-source, sibling of this repo)
#   MANIFEST    manifest git URL or directory
#               (default: this iso-build checkout; must have default.xml committed)
#
# Adoption of pre-existing manual checkouts: any manifest path that already
# exists but is not repo-managed is moved to "<path>.legacy" and re-cloned
# from that local directory via a url.insteadOf rewrite (no network, history
# preserved, committed state only).  Remote URLs are canonicalised again
# afterwards.  The .legacy directories are left in place for review; delete
# them once you are happy.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
WORKSPACE="${WORKSPACE:-$(cd "$HERE/.." && pwd)/gnome-source}"
MANIFEST="${MANIFEST:-$HERE}"
TOOL="$WORKSPACE/.repo-tools/git-repo"
CANON="https://github.com/Matrinsoft/"

[ -d "$WORKSPACE" ] || { echo "ERROR: workspace $WORKSPACE not found" >&2; exit 1; }
[ -f "$MANIFEST/default.xml" ] || { echo "ERROR: $MANIFEST/default.xml not found" >&2; exit 1; }
# repo init clones the manifest repo, which only contains COMMITTED files.
if [ -d "$MANIFEST/.git" ]; then
  git -C "$MANIFEST" ls-files --error-unmatch default.xml >/dev/null 2>&1 || {
    echo "ERROR: $MANIFEST/default.xml exists but is not committed;" >&2
    echo "       repo init clones committed state only. Commit it first." >&2
    exit 1
  }
fi

echo "=== workspace: $WORKSPACE"
echo "=== manifest:  $MANIFEST"

# 1. git-repo tool. Full clone on purpose: the launcher bootstraps itself
#    from its own .git, and a shallow source rejects the ref fetch.
if [ ! -x "$TOOL/repo" ]; then
  echo "=== cloning git-repo tool"
  mkdir -p "$(dirname "$TOOL")"
  git clone https://github.com/GerritCodeReview/git-repo.git "$TOOL"
fi

# git-repo rejects "~" in manifest paths (a Windows 8.3 guard); Fedora
# component directories legitimately contain "~" (e.g. 51~beta-1).  Patch the
# vendored tool and keep the patch COMMITTED inside it so that .repo/repo
# (a clone of this checkout) receives it too.  Linux-only workspace: harmless.
patch_tilde() {
  [ -f "$1" ] || return 0
  if grep -q 'False and "~" in path' "$1"; then return 0; fi
  sed -i 's/if "~" in path:/if False and "~" in path:/' "$1"
}
patch_tilde "$TOOL/manifest_xml.py"
if [ -d "$TOOL/.git" ] && ! git -C "$TOOL" diff --quiet -- manifest_xml.py; then
  git -C "$TOOL" -c user.email=sync@lingmo.local -c user.name='repo-sync' \
      add manifest_xml.py
  git -C "$TOOL" -c user.email=sync@lingmo.local -c user.name='repo-sync' \
      commit -qm 'allow "~" in manifest paths (Linux workspace)'
fi

# Local manifest sources need uploadpack filters for --partial-clone.
if [ -d "$MANIFEST" ]; then
  git -C "$MANIFEST" config uploadpack.allowFilter true
fi

cd "$WORKSPACE"

# 2. adopt foreign checkouts (built as GIT_CONFIG_* overrides for the sync)
declare -a K V
NK=0
while IFS=$'\t' read -r path name rev; do
  managed=0
  if [ -e "$path" ]; then
    if [ -L "$path/.git" ]; then
      case "$(readlink "$path/.git")" in
        *"/.repo/"*) managed=1 ;;             # already repo-managed
      esac
    elif [ -f "$path/.git" ]; then
      managed=1                               # submodule worktree: leave alone
    fi
    if [ "$managed" = 0 ]; then
      echo "=== adopting foreign checkout: $path -> $path.legacy"
      mv "$path" "$path.legacy"
    fi
  fi
  # Register an insteadOf rule for EVERY project: git picks the longest
  # matching prefix, so ".../anaconda" would otherwise hijack fetch URLs of
  # ".../anaconda-l10n" (and every other name extending a shorter one).
  if [ -e "$path.legacy" ] && [ ! -e "$path" -o "$managed" = 1 ]; then
    if [ -d "$path.legacy" ]; then
      git -C "$path.legacy" config uploadpack.allowFilter true  # partial-clone
      # Detached legacy clones (no refs/heads/<rev>) cannot serve repo's
      # "+refs/heads/<rev>" fetch: create the branch from origin if missing.
      if ! git -C "$path.legacy" show-ref --verify --quiet "refs/heads/$rev"; then
        if git -C "$path.legacy" show-ref --verify --quiet "refs/remotes/origin/$rev"; then
          git -C "$path.legacy" update-ref "refs/heads/$rev" "refs/remotes/origin/$rev"
          echo "    created refs/heads/$rev in $path.legacy"
        else
          echo "    WARN: $path.legacy has no origin/$rev to branch from" >&2
        fi
      fi
    fi
    K[$NK]="url.$WORKSPACE/$path.legacy.insteadOf"
    V[$NK]="$CANON$name"
    NK=$((NK+1))
  else
    # No local copy: identity rule so a shorter prefix still cannot win.
    K[$NK]="url.$CANON$name.insteadOf"
    V[$NK]="$CANON$name"
    NK=$((NK+1))
  fi
done < <(python3 - "$MANIFEST/default.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
dflt = root.find("default")
drev = dflt.get("revision") if dflt is not None else None
for p in root.findall("project"):
    print("%s\t%s\t%s" % (p.get("path"), p.get("name"),
                          p.get("revision") or drev or "main"))
PY
)

# 3. repo init + sync
if [ "$NK" -gt 0 ]; then
  export GIT_CONFIG_COUNT="$NK"
  for ((i=0; i<NK; i++)); do
    export "GIT_CONFIG_KEY_$i=${K[$i]}"
    export "GIT_CONFIG_VALUE_$i=${V[$i]}"
  done
fi

echo "=== repo init"
"$TOOL/repo" init -q --partial-clone -b main -u "$MANIFEST"
# The runtime copy at .repo/repo may predate the patch above.
patch_tilde "$WORKSPACE/.repo/repo/manifest_xml.py"
echo "=== repo sync"
"$TOOL/repo" sync "$@"
unset GIT_CONFIG_COUNT GIT_CONFIG_KEY_ GIT_CONFIG_VALUE_ || true

# 4. canonicalise remote URLs (clone-time rewrites may have left local paths)
while IFS=$'\t' read -r path name; do
  [ -d "$path/.git" ] || [ -L "$path/.git" ] || continue
  rname=$(git -C "$path" remote 2>/dev/null | head -1)
  [ -n "$rname" ] || continue
  git -C "$path" remote set-url "$rname" "$CANON$name"
done < <(python3 - "$MANIFEST/default.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
for p in ET.parse(sys.argv[1]).getroot().findall("project"):
    print("%s\t%s" % (p.get("path"), p.get("name")))
PY
)

# 5. initialise git submodules (vte291, anaconda, anaconda-webui)
while IFS= read -r path; do
  [ -d "$path" ] || continue
  # Some trees carry stray gitlinks without any .gitmodules (vte291 has
  # meson wrap checkouts committed as gitlinks) - nothing to initialise there.
  [ -f "$path/.gitmodules" ] || continue
  echo "=== submodules: $path"
  git -C "$path" submodule update --init --recursive
done < <(python3 - "$MANIFEST/default.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
for p in ET.parse(sys.argv[1]).getroot().findall("project"):
    print(p.get("path"))
PY
)

echo "=== sync finished"
ls -d "$WORKSPACE"/*.legacy 2>/dev/null | sed 's/^/    adopted: /' || true
