%post
# Ensure Lingmo OS branding is present
if [ -f /usr/lib/os-release ]; then
  sed -i 's/^PRETTY_NAME=.*/PRETTY_NAME="Lingmo OS 5 (Unstable)"/' /usr/lib/os-release || true
fi

# Minimal image boots to a text console
systemctl set-default multi-user.target

# Enable NetworkManager
systemctl enable NetworkManager
%end
