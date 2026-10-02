%post
# --- SELinux: label the rootfs (MANDATORY for boot) ---
# livecd-creator never runs setfiles, so the image would ship with zero
# security.selinux xattrs (every file unlabeled_t). At switch-root the
# exec of an unlabeled /usr/lib/systemd/systemd performs no
# type_transition, so PID1 stays kernel_t instead of becoming init_t.
# kernel_t has no process setfscreate/setrlimit, so manager_new's
# mkdir_label("/run/systemd/units") fails with EACCES and systemd aborts
# with "Failed to allocate manager object: Permission denied" (the
# machine freezes in early boot). Pseudo filesystems are excluded;
# /run created by the initrd is safe afterwards because init_t has
# create/mounton on non_security_file_type dirs (init_create_dirs).
setfiles -F \
    -e /proc -e /sys -e /dev -e /run -e /tmp \
    /etc/selinux/targeted/contexts/files/file_contexts /

# Verify: ls -Z prints "?" for unlabeled files; fail the build if the
# init_exec_t label (the kernel_t -> init_t transition trigger) is absent.
ctx="$(ls -Z /usr/lib/systemd/systemd 2>/dev/null)"
case "$ctx" in
  *init_exec_t*) ;;
  *) echo "ERROR: SELinux labeling failed: /usr/lib/systemd/systemd -> '$ctx'" >&2
     exit 1 ;;
esac
%end
