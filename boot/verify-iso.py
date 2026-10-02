#!/usr/bin/env python3
"""Verify the ISO actually contains the boot payload.

A dracut check failure during the image build (e.g. missing dracut-live)
leaves no initramfs, and imgcreate silently skips initrd0.img instead of
erroring - that produced an unbootable published ISO once. Fail the build
here so a broken ISO never reaches the release upload step.

Usage: verify-iso.py <path-to-iso>
"""

import struct
import sys

SECTOR = 2048
REQUIRED = {
    "/ISOLINUX/INITRD0.IMG": 1 << 20,   # initramfs must be > 1 MiB
    "/ISOLINUX/VMLINUZ0": 1 << 20,      # kernel
    "/LIVEOS/SQUASHFS.IMG": 1 << 20,    # rootfs image
    "/EFI/BOOT/BOOTX64.EFI": 1,         # EFI bootloader
}


def main():
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
        print('CI log for "Module \'...\' cannot be found".')
        sys.exit(1)
    print("ISO content check passed:")
    for path in sorted(REQUIRED):
        print("  %s  %d bytes" % (path, files[path]))


if __name__ == "__main__":
    main()
