#!/usr/bin/env python3
"""Render lingmo-live.ks from core/ks fragments and Kconfig values.

Usage:
  render-ks.py [--config FILE] [--out FILE] [--check]

With no --config, uses $KCONFIG_CONFIG or .config if present, otherwise
falls back to the Kconfig defaults (so a bare CI checkout renders the
same file as before the split).
"""

import argparse
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "scripts"))

import kconfiglib  # noqa: E402

FRAG_DIR = os.path.join(ROOT, "core", "ks")

# ISO type -> fragment list (order matters; fragments are joined by one
# blank line, reproducing the original monolithic layout exactly).
TYPES = {
    "DESKTOP": [
        "00-header.ks",
        "10-packages-desktop.ks",
        "20-post-desktop.ks",
    ],
    "SERVER": [
        "00-header.ks",
        "10-packages-server.ks",
        "20-post-server.ks",
        "20-post-common.ks",
    ],
    "MINIMAL": [
        "00-header.ks",
        "10-packages-minimal.ks",
        "20-post-minimal.ks",
        "20-post-common.ks",
    ],
    "INSTALLABLE": [
        "00-header.ks",
        "10-packages-installable.ks",
        "20-post-installable.ks",
        "20-post-common.ks",
    ],
}

TOKENS = (
    "SYS_LANG",
    "SYS_KEYBOARD",
    "SYS_TIMEZONE",
    "ROOT_SIZE_MB",
    "LIVE_USER",
    "LIVE_PASSWORD",
    "FEDORA_MIRROR",
)


def iso_type(kconf):
    for name in TYPES:
        if kconf.syms["ISO_TYPE_" + name].tri_value == 2:  # y
            return name
    raise SystemExit("render-ks: no ISO type selected in configuration")


def render(kconf, iso):
    values = {t: kconf.syms[t].str_value for t in TOKENS}
    parts = []
    for frag in TYPES[iso]:
        path = os.path.join(FRAG_DIR, frag)
        with open(path, encoding="utf-8") as f:
            text = f.read()
        for key, val in values.items():
            text = text.replace("@" + key + "@", val)
        # unresolved tokens look like @UPPER_CASE@; kickstart group names
        # (@core) and unit specifiers (getty@tty1) never match this.
        leftover = re.findall(r"@[A-Z][A-Z0-9_]*@", text)
        if leftover:
            raise SystemExit(
                "render-ks: unresolved token(s) in %s: %s"
                % (frag, ", ".join(sorted(set(leftover))))
            )
        parts.append(text.rstrip("\n"))
    # one blank line between fragments (the file's section separators)
    return "\n\n".join(parts) + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--config", help="configuration file (default: $KCONFIG_CONFIG or .config)")
    ap.add_argument("--out", default=os.path.join(ROOT, "lingmo-live.ks"))
    ap.add_argument("--check", action="store_true", help="compare with --out instead of writing")
    args = ap.parse_args()

    kconf = kconfiglib.Kconfig(os.path.join(ROOT, "Kconfig"))
    cfg = args.config or os.environ.get("KCONFIG_CONFIG") or os.path.join(ROOT, ".config")
    if os.path.exists(cfg):
        kconf.load_config(cfg)

    iso = iso_type(kconf)
    output = render(kconf, iso)

    if args.check:
        try:
            with open(args.out, encoding="utf-8") as f:
                current = f.read()
        except FileNotFoundError:
            current = None
        if current == output:
            print("render-ks: %s is up to date (%s)" % (args.out, iso))
            return
        sys.stderr.write("render-ks: %s differs from rendered %s output\n" % (args.out, iso))
        sys.exit(1)

    with open(args.out, "w", encoding="utf-8", newline="\n") as f:
        f.write(output)
    print("render-ks: wrote %s (%s)" % (args.out, iso))


if __name__ == "__main__":
    main()
