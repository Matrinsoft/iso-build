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
# Fedora 45 / RPM 6.0: %_pkgverify_level defaults to "all" (valid signature
# AND digest required at RPM transaction level). This bypasses dnf's
# nocrypto/gpgcheck handling and fails the transaction test with
# "does not verify: NOKEY / no signature" for unsigned self-built RPMs and
# packages whose signing key is not in the installroot rpmdb.
# Documented workaround for the F45 signature-enforcement change:
# https://fedoraproject.org/wiki/Changes/Enforcing_signature_checking_by_default
mkdir -p /etc/rpm
echo '%_pkgverify_level digest' > /etc/rpm/macros.verify
echo "rpm pkgverify_level: $(rpm --eval '%_pkgverify_level')"
# Point the kickstart's lingmo repo at the freshly built local repo
sed -i "s|repo --name=lingmo --baseurl=.*|repo --name=lingmo --baseurl=file://$REPO_DIR --cost=1|" "$WORK_DIR/lingmo-live.ks"

# Self-built rpms are unsigned; Fedora 45 branched key may be missing in the
# build container. livecd-creator's imgcreate writes its own dnf.conf (which
# does not read the global dnf.conf), so patch its dnf backend.
#
# The "package ... does not verify: NOKEY / no signature" error is raised by
# RPM's transaction test (dnf.base.do_transaction -> self._ts.test()). RPM
# only skips signature verification when the `nocrypto` tsflag is set, which
# dnf maps to RPMVSF_NOSIGNATURES|RPMVSF_NODIGESTS (dnf/base.py:638-645).
# Setting gpgcheck=0 alone is NOT sufficient. Also force gpgcheck off per
# repo to satisfy dnf's own download-time _sig_check_pkg().
python3 - <<'PYEOF'
import glob
f = glob.glob("/usr/lib/python*/site-packages/imgcreate/dnfinst.py")
assert f, "imgcreate dnfinst.py not found"
f = f[0]
s = open(f).read()

# 1) Add the `nocrypto` tsflag (RPM-level sig check off) + gpgcheck=0 in
#    the generated [main] dnf.conf.
needle_main = 'conf += "tsflags=nocontexts\\n"'
patch_main = 'conf += "tsflags=nocontexts,nocrypto\\n"\n        conf += "gpgcheck=0\\n"\n        conf += "repo_gpgcheck=0\\n"'
if needle_main in s:
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
print("patched nocrypto+gpgcheck=0 into", f)
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

# Gate: verify the ISO actually contains the boot payload before BUILD_DONE.
# A dracut check failure during the image build (e.g. missing dracut-live)
# leaves no initramfs, and imgcreate silently skips initrd0.img instead of
# erroring — that produced an unbootable published ISO once. Fail the build
# here so a broken ISO never reaches the release upload step.
python3 - "$ISO_OUT" <<'PYEOF'
import struct, sys

SECTOR = 2048
REQUIRED = {
    "/ISOLINUX/INITRD0.IMG": 1 << 20,   # initramfs must be > 1 MiB
    "/ISOLINUX/VMLINUZ0": 1 << 20,      # kernel
    "/LIVEOS/SQUASHFS.IMG": 1 << 20,    # rootfs image
    "/EFI/BOOT/BOOTX64.EFI": 1,         # EFI bootloader
}

with open(sys.argv[1], "rb") as f:
    f.seek(16 * SECTOR)
    pvd = f.read(SECTOR)
    if pvd[0] != 1 or pvd[1:6] != b"CD001":
        sys.exit("FATAL: not an ISO9660 image (no primary volume descriptor)")
    root = pvd[156:190]
    files = {}

    def walk(lba, size, prefix):
        f.seek(lba * SECTOR)
        data = f.read(size)
        off = 0
        while off + 34 <= size:
            reclen = data[off]
            if reclen < 34:                      # padding / end of sector
                off = (off // SECTOR + 1) * SECTOR
                continue
            flags = data[off + 25]
            nlen = data[off + 32]
            name = data[off + 33:off + 33 + nlen]
            lba_c = struct.unpack_from("<I", data, off + 2)[0]
            size_c = struct.unpack_from("<I", data, off + 10)[0]
            off += reclen
            if name in (b"\x00", b"\x01"):       # "." and ".."
                continue
            n = name.decode("ascii", "replace").split(";")[0].rstrip(".").upper()
            path = prefix + "/" + n
            if flags & 0x02:
                walk(lba_c, size_c or SECTOR, path)
            else:
                files[path] = size_c

    walk(struct.unpack_from("<I", root, 2)[0],
         struct.unpack_from("<I", root, 10)[0], "")

errors = []
for path, min_size in REQUIRED.items():
    if path not in files:
        errors.append("MISSING: " + path)
    elif files[path] < min_size:
        errors.append("TOO SMALL: %s (%d bytes < %d)" % (path, files[path], min_size))

if errors:
    print("=== ISO content check FAILED ===")
    for e in errors:
        print("  " + e)
    print('Known cause: dracut check failure during image build; search the')
    print("CI log for \"Module '...' cannot be found\".")
    sys.exit(1)
print("ISO content check passed:")
for path in sorted(REQUIRED):
    print("  %s  %d bytes" % (path, files[path]))
PYEOF

echo "BUILD_DONE"
