%packages
# --- Core system groups ---
@core
@standard
@networkmanager-submodules
@fonts
@multimedia

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
plymouth
plymouth-system-theme
plymouth-theme-spinner

# --- System services ---
systemd
systemd-udev
NetworkManager
NetworkManager-wifi
NetworkManager-bluetooth
firewalld
polkit
upower

# --- Audio / video stack ---
pipewire
pipewire-pulseaudio
pipewire-alsa
wireplumber

# --- Mesa (from Fedora repo) ---
mesa-dri-drivers
mesa-libgbm
mesa-vulkan-drivers

# --- Lingmo OS identity ---
lingmo-release

# --- Self-built GNOME packages (overrides Fedora's) ---
accountsservice
adobe-source-code-pro-fonts
avahi
baobab
dconf
decibels
fprintd
gdm
geoclue2
gjs
glib-networking
glib2
gnome-backgrounds
gnome-bluetooth
gnome-boxes
gnome-browser-connector
gnome-calculator
gnome-calendar
gnome-characters
gnome-clocks
gnome-color-manager
gnome-connections
gnome-contacts
gnome-control-center
gnome-disk-utility
gnome-epub-thumbnailer
gnome-font-viewer
gnome-initial-setup
gnome-logs
gnome-maps
gnome-remote-desktop
gnome-session
gnome-settings-daemon
gnome-shell
gnome-software
gnome-system-monitor
gnome-text-editor
gnome-user-docs
gnome-weather
gsettings-desktop-schemas
gtk4
gvfs
libadwaita
localsearch
mutter
nautilus
PackageKit
ptyxis
rygel
sane-backends
showtime
simple-scan
sushi
tinysparql
vte291
xdg-desktop-portal
xdg-desktop-portal-gnome
xdg-desktop-portal-gtk
xdg-user-dirs-gtk
yelp

# --- Components intentionally taken from Fedora repo (not self-built) ---
gst-thumbnailers
gnome-user-share
loupe
snapshot
librsvg2
papers

# --- Extra desktop essentials ---
gnome-terminal
gnome-tweaks
firefox
network-manager-applet

%end
