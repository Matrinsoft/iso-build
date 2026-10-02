#!/usr/bin/env python3
"""Patch imgcreate's dnf backend so unsigned self-built RPMs install.

Fedora 45 / RPM 6.0: %_pkgverify_level defaults to "all" (valid signature
AND digest required at RPM transaction level). This bypasses dnf's
nocrypto/gpgcheck handling and fails the transaction test with
"does not verify: NOKEY / no signature" for unsigned self-built RPMs and
packages whose signing key is not in the installroot rpmdb.
Documented workaround for the F45 signature-enforcement change:
https://fedoraproject.org/wiki/Changes/Enforcing_signature_checking_by_default

Self-built rpms are unsigned; Fedora 45 branched key may be missing in the
build container. livecd-creator's imgcreate writes its own dnf.conf (which
does not read the global dnf.conf), so patch its dnf backend.

The "package ... does not verify: NOKEY / no signature" error is raised by
RPM's transaction test (dnf.base.do_transaction -> self._ts.test()). RPM
only skips signature verification when the `nocrypto` tsflag is set, which
dnf maps to RPMVSF_NOSIGNATURES|RPMVSF_NODIGESTS (dnf/base.py:638-645).
Setting gpgcheck=0 alone is NOT sufficient. Also force gpgcheck off per
repo to satisfy dnf's own download-time _sig_check_pkg().
"""

import glob
import sys

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
