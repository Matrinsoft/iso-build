#!/usr/bin/env python3
"""Shared helpers for the pkg/ build chain."""

import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANIFEST = os.path.join(REPO_ROOT, "default.xml")
REPOS_TXT = os.path.join(REPO_ROOT, "repos.txt")

# Component groups of default.xml; a package's tree is looked up there first
# (installer/ also carries short-name repos but they are not RPM components).
GROUPS = ("apps", "core", "desktop", "external")


def symbol_for(shortname):
    """pkg/Kconfig symbol for a repos.txt short name."""
    return "PKG_" + re.sub(r"[^A-Za-z0-9]", "_", shortname).upper()


def load_manifest():
    """[(name, path), ...] in document order."""
    root = ET.parse(MANIFEST).getroot()
    return [(p.get("name"), p.get("path")) for p in root.findall("project")]


def read_repos():
    """repos.txt short names, one per line."""
    with open(REPOS_TXT) as f:
        return [l.strip() for l in f if l.strip() and not l.startswith("#")]


def find_tree(shortname):
    """Source checkout directory for a repos.txt short name."""
    cands = [path for name, path in load_manifest() if name == shortname]
    if not cands:
        raise SystemExit(
            "build-pkg: %r not found in default.xml (add it to the manifest)" % shortname
        )
    # Prefer component groups, then the first checkout that holds a spec file.
    cands.sort(key=lambda p: (p.split("/", 1)[0] not in GROUPS, p))
    for rel in cands:
        tree = workspace_path(rel)
        if os.path.isdir(tree) and any(
            f.endswith(".spec") for f in os.listdir(tree)
        ):
            return tree
    raise SystemExit(
        "build-pkg: no checkout with a .spec for %r; run 'make sync' first"
        % shortname
    )


def workspace_path(rel):
    ws = os.environ.get(
        "WORKSPACE", os.path.join(os.path.dirname(REPO_ROOT), "gnome-source")
    )
    return os.path.join(ws, rel)


def find_spec(tree, shortname):
    specs = sorted(f for f in os.listdir(tree) if f.endswith(".spec"))
    if not specs:
        raise SystemExit("build-pkg: no .spec in " + tree)
    prefer = shortname + ".spec"
    if prefer in specs:
        return os.path.join(tree, prefer)
    if len(specs) == 1:
        return os.path.join(tree, specs[0])
    raise SystemExit(
        "build-pkg: several specs in %s (%s); add pkg/%s.mk override"
        % (tree, ", ".join(specs), shortname)
    )


def parse_spec(spec_path):
    """(name, version, [(kind, number, ref), ...]) for Source/Patch fields."""
    name = version = None
    refs = []
    with open(spec_path, errors="replace") as f:
        for line in f:
            m = re.match(r"^(Name|Version):\s*(\S+)", line)
            if m:
                if m.group(1) == "Name" and name is None:
                    name = m.group(2)
                elif m.group(1) == "Version" and version is None:
                    version = m.group(2)
                continue
            m = re.match(r"^(Source|Patch)(\d*):\s*(\S+)", line)
            if m:
                refs.append((m.group(1), m.group(2), m.group(3)))
    if not name or not version:
        raise SystemExit("build-pkg: cannot read Name/Version from " + spec_path)
    return name, version, refs


def expand(ref, name, version):
    return (
        ref.replace("%{name}", name)
        .replace("%{version}", version)
        .replace("%{Name}", name)
        .replace("%{Version}", version)
        # Common in GNOME specs, defined by %gnome_check_version inside the
        # spec at build time; the tarball version equals the package version.
        .replace("%{gnome_tarball_version}", version)
        .replace("%{url_version}", version)
    )


def spec_fields(spec_path):
    """(name, version, refs) with macros resolved via rpmspec -P.

    Some specs (fonts template) generate the Name field from macros, so the
    raw file alone is not enough; fall back to raw parsing when rpmspec is
    unavailable or fails.
    """
    name = version = None
    refs = []
    try:
        out = subprocess.run(
            ["rpmspec", "-P", spec_path],
            capture_output=True, text=True, check=True,
        ).stdout
        m = re.search(r"^Name:\s*(\S+)", out, re.M)
        if m:
            name = m.group(1)
        m = re.search(r"^Version:\s*(\S+)", out, re.M)
        if m:
            version = m.group(1)
        refs = re.findall(r"^(Source|Patch)(\d*):\s*(\S+)", out, re.M)
    except (OSError, subprocess.CalledProcessError):
        pass
    if not name or not version or not refs:
        rname, rversion, rrefs = parse_spec(spec_path)
        name = name or rname
        version = version or rversion
        if not refs:
            refs = [(k, n, expand(v, name, version)) for k, n, v in rrefs]
    if not name or not version:
        raise SystemExit("build-pkg: cannot read Name/Version from " + spec_path)
    return name, version, refs


ARCHIVE_RE = re.compile(
    r"\.(tar\.[A-Za-z0-9]+|tgz|tbz2|txz|tar\.gz|tar\.bz2|tar|zip)$"
)


def tar_cmd_for(ext, dest):
    if ext in (".tar.xz", ".txz"):
        return ["tar", "-cJf", dest]
    if ext in (".tar.gz", ".tgz"):
        return ["tar", "-czf", dest]
    if ext in (".tar.bz2", ".tbz2"):
        return ["tar", "-cjf", dest]
    if ext == ".tar.zst":
        return ["tar", "-c", "--zstd", "-f", dest]
    if ext == ".tar":
        return ["tar", "-cf", dest]
    return None


def run(cmd, **kw):
    r = subprocess.run(cmd, **kw)
    if r.returncode:
        raise SystemExit("build-pkg: command failed: %s" % " ".join(cmd))
    return r


def build_one(shortname):
    import shutil

    tree = find_tree(shortname)
    spec = find_spec(tree, shortname)
    name, version, refs = spec_fields(spec)
    top = os.path.join(REPO_ROOT, "out", "pkg", shortname)
    sources = os.path.join(top, "SOURCES")
    if os.path.isdir(sources):
        shutil.rmtree(sources)
    os.makedirs(sources)

    for kind, num, raw in refs:
        target_name = expand(raw.rsplit("/", 1)[-1], name, version)
        dest = os.path.join(sources, target_name)
        present = os.path.join(tree, target_name)
        if os.path.isfile(present):
            os.symlink(os.path.abspath(present), dest)
            continue
        m = ARCHIVE_RE.search(target_name)
        if kind == "Source" and m:
            # Re-tar the unpacked upstream directory that ships in the tree
            # (Fedora SRPM layouts keep <name>-<version>/ instead of Source0).
            ext = m.group(0)
            src_dir = os.path.join(tree, "%s-%s" % (name, version))
            if not os.path.isdir(src_dir):
                cands = [d for d in os.listdir(tree)
                         if os.path.isdir(os.path.join(tree, d))
                         and not d.startswith(".")]
                if len(cands) == 1:
                    src_dir = os.path.join(tree, cands[0])
                else:
                    raise SystemExit(
                        "build-pkg: %s: cannot locate source dir for %s "
                        "(candidates: %s); add pkg/%s.mk override"
                        % (shortname, target_name, cands, shortname))
            cmd = tar_cmd_for(ext, dest)
            if cmd is None:
                raise SystemExit(
                    "build-pkg: %s: unsupported archive type %s" % (shortname, ext))
            print("build-pkg: %s: packing %s -> %s"
                  % (shortname, os.path.basename(src_dir), target_name))
            run(cmd + ["-C", tree, os.path.basename(src_dir)])
            continue
        raise SystemExit(
            "build-pkg: %s: %s missing from tree (%s)"
            % (shortname, target_name, present))

    cmd = ["rpmbuild", "-ba", spec, "--define", "_topdir " + top]
    dist = os.environ.get("DIST")
    if dist:
        cmd += ["--define", "dist " + dist]
    print("build-pkg: %s: %s" % (shortname, " ".join(cmd)))
    run(cmd)

    rpms = []
    for root, _dirs, files in os.walk(os.path.join(top, "RPMS")):
        rpms += [os.path.join(root, f) for f in files if f.endswith(".rpm")]
    srpm_dir = os.path.join(top, "SRPMS")
    srpms = ([os.path.join(srpm_dir, f) for f in os.listdir(srpm_dir)
              if f.endswith(".rpm")] if os.path.isdir(srpm_dir) else [])
    if not rpms:
        raise SystemExit("build-pkg: %s: no RPM produced" % shortname)

    repo = os.environ.get("REPO_DIR", "/tmp/lingmo-repo")
    os.makedirs(repo, exist_ok=True)
    for rpm in rpms + srpms:
        shutil.copy2(rpm, repo)
    print("build-pkg: %s: %d RPM(s) -> %s" % (shortname, len(rpms), repo))
    if shutil.which("createrepo_c"):
        run(["createrepo_c", "--update", repo])
    else:
        print("build-pkg: note: createrepo_c not installed; run it on %s "
              "before the ISO build" % repo)
    return rpms


def enabled_packages(config_path):
    """Short names whose PKG_<SYM> evaluates to y in Kconfig + .config."""
    sys.path.insert(0, os.path.join(REPO_ROOT, "scripts"))
    import kconfiglib

    kconf = kconfiglib.Kconfig(os.path.join(REPO_ROOT, "Kconfig"))
    if os.path.isfile(config_path):
        kconf.load_config(config_path, replace=False)
    names = []
    for n in read_repos():
        sym = kconf.syms.get(symbol_for(n))
        if sym is not None and sym.str_value == "y":
            names.append(n)
    return names


def main(argv):
    if not argv:
        raise SystemExit(
            "usage: build_pkg.py [--all [config] | --list [config] | <name>...]")
    if argv[0] == "--all":
        names = enabled_packages(argv[1] if len(argv) > 1 else ".config")
        if not names:
            raise SystemExit("build-pkg: no PKG_*=y in .config (make defconfig)")
    elif argv[0] == "--list":
        names = enabled_packages(argv[1] if len(argv) > 1 else ".config")
        print("\n".join(names))
        return
    else:
        names = argv
    for n in names:
        build_one(n)


if __name__ == "__main__":
    try:
        sys.stdout.reconfigure(line_buffering=True)
    except AttributeError:
        pass
    main(sys.argv[1:])
