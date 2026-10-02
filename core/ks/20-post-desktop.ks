%post
# Ensure Lingmo OS branding is present
if [ -f /usr/lib/os-release ]; then
  sed -i 's/^PRETTY_NAME=.*/PRETTY_NAME="Lingmo OS 5 (Unstable)"/' /usr/lib/os-release || true
fi

# Enable graphical boot target
systemctl set-default graphical.target

# Enable GDM
systemctl enable gdm

# --- GDM: keep kmscon off tty1 or autologin gets replaced by a greeter ---
# kmscon.service is pulled in by multi-user.target and claims tty1 at
# the moment GDM registers its display. gdm.service only Conflicts with
# getty@tty1 and kmsconvt@tty1, so kmscon.service survives; the VT/uevent
# wakes the display factory, which builds a greeter session on top of
# the liveuser session (the first one dies with "Session never
# registered") and the login screen permanently replaces the desktop.
# A/B test on the 20260928 image: with these two units masked, no
# greeter session is ever created and the desktop stays up.
systemctl disable kmscon.service
systemctl disable kmsconvt@tty1.service

# Enable NetworkManager
systemctl enable NetworkManager

# --- Live user: create the account GDM will auto-login ---
# The kickstart `user` command is silently ignored by livecd-creator, so
# without this the image has no login account at all (root is locked) and
# autologin fails: GDM falls back to a getty and the ttys accept nothing.
if ! id @LIVE_USER@ >/dev/null 2>&1; then
  useradd -m -u 1000 -G wheel @LIVE_USER@
  echo '@LIVE_USER@:@LIVE_PASSWORD@' | chpasswd
fi

# --- GDM: auto-login the live user (standard live-image behavior) ---
# The image has no other account (root is locked), so without this the
# system is unusable: GDM shows an empty user list and the ttys accept
# no login. Overwriting custom.conf is safe: every key in it is optional
# and WaylandEnable defaults to true.
cat > /etc/gdm/custom.conf <<'EOF'
[daemon]
AutomaticLoginEnable=true
AutomaticLogin=@LIVE_USER@
EOF

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
