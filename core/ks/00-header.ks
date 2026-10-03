# Lingmo OS 5 (Unstable) — GNOME live image
# Build with: livecd-creator --config lingmo-live.ks --fslabel=LingmoOS_5

lang @SYS_LANG@
keyboard @SYS_KEYBOARD@
timezone @SYS_TIMEZONE@
rootpw --lock --iscrypted locked

# Live user: created in %post (the kickstart `user` command is silently
# ignored by livecd-creator — verified: built /etc/passwd has no liveuser).
# GDM auto-logs it in at boot.

# Root filesystem image size (MB). Default is 4GB, which the full GNOME
# image plus firmware exceeds; give ourselves comfortable headroom.
part / --size=@ROOT_SIZE_MB@

# Fedora 45 repository (branched/development stage, not yet formally released)
repo --name=fedora --baseurl=@FEDORA_MIRROR@/development/45/Everything/x86_64/os/ --cost=200
repo --name=fedora-updates --baseurl=@FEDORA_MIRROR@/updates/45/Everything/x86_64/ --cost=300

# Lingmo OS repository (self-built packages, highest priority)
# NOTE: build-iso.sh generates /tmp/lingmo-repo and rewrites this line's baseurl.
repo --name=lingmo --baseurl=file:///tmp/lingmo-repo --cost=1
