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
