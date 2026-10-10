# Lingmo OS 5 (Unstable) — GNOME live image
# Build with: livecd-creator --config lingmo-live.ks --fslabel=LingmoOS_5

lang en_US.UTF-8
keyboard us
timezone UTC
rootpw --lock --iscrypted locked

# Live user: created in %post (the kickstart `user` command is silently
# ignored by livecd-creator — verified: built /etc/passwd has no liveuser).
# GDM auto-logs it in at boot.

# Root filesystem image size (MB). Default is 4GB, which the full GNOME
# image plus firmware exceeds; give ourselves comfortable headroom.
part / --size=8192

# Fedora 45 repository (branched/development stage, not yet formally released)
repo --name=fedora --baseurl=https://dl.fedoraproject.org/pub/fedora/linux/development/45/Everything/x86_64/os/ --cost=200
repo --name=fedora-updates --baseurl=https://dl.fedoraproject.org/pub/fedora/linux/updates/45/Everything/x86_64/ --cost=300

# Lingmo OS repository (self-built packages, highest priority)
# NOTE: build-iso.sh generates /tmp/lingmo-repo and rewrites this line's baseurl.
repo --name=lingmo --baseurl=file:///tmp/lingmo-repo --cost=1

%packages
# --- Core system groups ---
@core
@standard
@networkmanager-submodules

# --- SELinux ---
# policycoreutils ships setfiles, which %post uses to label the rootfs
# (livecd-creator never runs setfiles itself). selinux-policy-targeted
# arrives via @core but is listed explicitly: boot hard-depends on it.
selinux-policy-targeted
policycoreutils

# --- Boot / init ---
kernel
kernel-modules
kernel-modules-extra
dracut
# dracut-live provides 70livenet + 70dmsquash-live, which imgcreate hardcodes
# into /etc/dracut.conf.d/99-liveos.conf (add_dracutmodules+=" livenet
# dmsquash-live pollcdrom "). Without it, dracut exits 1 during kernel install
# ("Module 'livenet' cannot be found.") and no initramfs is built, so
# initrd0.img is silently missing from the ISO.
dracut-live
# livenet's depends() includes "network" (70network/40network lives in
# dracut-network). Without it, dracut fails with
# "Module 'livenet' depends on module 'network', which can't be installed".
dracut-network
# url-lib's check() requires the curl binary (livenet depends on url-lib).
curl
dracut-config-generic
grub2-efi-x64
grub2-efi-x64-cdboot
grub2-tools
grub2-tools-minimal
shim-x64
efibootmgr
plymouth
plymouth-system-theme
plymouth-theme-spinner

# --- System services ---
systemd
systemd-udev
NetworkManager
firewalld
polkit
upower

# --- Lingmo OS identity ---
lingmo-release

# --- Installer payload (Anaconda WebUI) ---
# Runtime dependencies are pulled in by dnf automatically; the WebUI serves
# the installer on localhost:8080 and via sshd for remote machines.
anaconda
anaconda-webui
openssh-server
# input device/keyboard tables used by anaconda's language & keyboard steps
langtable

%end

%post
# Ensure Lingmo OS branding is present
if [ -f /usr/lib/os-release ]; then
  sed -i 's/^PRETTY_NAME=.*/PRETTY_NAME="Lingmo OS 5 (Unstable)"/' /usr/lib/os-release || true
fi

# Installer image: boot to a text target. anaconda-webui serves its UI on
# localhost:8080; instructions are printed to the console by the installer
# itself. No GDM/liveuser on this image type.
systemctl set-default multi-user.target

# Enable NetworkManager
systemctl enable NetworkManager

# Remote access for the WebUI (ssh port + anaconda's own listener)
systemctl enable sshd
systemctl enable firewalld

%end

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
