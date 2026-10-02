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
# dracut-network) and "url-lib" (needs the curl binary, already pulled in).
# Without dracut-network, dracut fails with
# "Module 'livenet' depends on module 'network', which can't be installed".
dracut-network
# url-lib's check() requires the curl binary (livenet depends on url-lib);
# declare it explicitly instead of relying on a transitive pull-in.
curl
dracut-config-generic
grub2-efi-x64
grub2-efi-x64-cdboot
grub2-tools
grub2-tools-minimal
shim-x64
efibootmgr

# --- System services ---
systemd
systemd-udev
NetworkManager
NetworkManager-wifi
firewalld
polkit
openssh-server

# --- Lingmo OS identity ---
lingmo-release

%end
