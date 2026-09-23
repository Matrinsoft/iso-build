# Lingmo OS 5 (Unstable) — GNOME live image
# Build with: livecd-creator --config lingmo-live.ks --fslabel=LingmoOS_5

lang en_US.UTF-8
keyboard us
timezone UTC
rootpw --lock --iscrypted locked

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
@fonts
@multimedia

# --- Boot / init ---
kernel
kernel-modules
kernel-modules-extra
dracut
dracut-config-generic
grub2-efi-x64
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
glycin
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
gnome-shell-extensions
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
papers
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

# --- Extra desktop essentials ---
gnome-terminal
gnome-tweaks
nautilus
firefox
network-manager-applet

%end

%post
# Ensure Lingmo OS branding is present
if [ -f /usr/lib/os-release ]; then
  sed -i 's/^PRETTY_NAME=.*/PRETTY_NAME="Lingmo OS 5 (Unstable)"/' /usr/lib/os-release || true
fi

# Enable graphical boot target
systemctl set-default graphical.target

# Enable GDM
systemctl enable gdm

# Enable NetworkManager
systemctl enable NetworkManager

%end
