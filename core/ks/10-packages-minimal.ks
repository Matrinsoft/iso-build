%packages
# --- Core system groups ---
@core
@standard

# --- SELinux ---
selinux-policy-targeted
policycoreutils

# --- Boot / init ---
kernel
kernel-modules
kernel-modules-extra
dracut
dracut-live
dracut-network
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
NetworkManager

# --- Lingmo OS identity ---
lingmo-release

%end
