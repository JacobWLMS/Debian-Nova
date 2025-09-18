#!/bin/bash
set -euo pipefail

# --- Helper for GUI feedback ---
info() { zenity --info --width=400 --title="Nova Installer" --text="$1"; }
progress() { echo "$1" | zenity --progress --title="Nova Installer" --percentage="$1" --auto-close; }

info "Welcome to Nova Setup!
This will transform Debian Testing into Nova.
You'll get a minimal GNOME desktop with sane defaults.
Background services are enabled automatically.
Optional developer tools are available."

# Step 1: Essentials
progress 5
apt update && apt full-upgrade -y
apt install -y \
  sudo curl wget git git-lfs unzip bash-completion ca-certificates \
  htop neofetch man-db manpages manpages-dev \
  tar zip unzip p7zip-full

# Step 2: GNOME Core + Circle essentials
progress 20
apt install -y \
  gnome-core gdm3 gnome-control-center nautilus \
  gnome-terminal gnome-software gnome-software-plugin-flatpak \
  gnome-system-monitor gnome-tweaks gnome-disk-utility deja-dup \
  xdg-desktop-portal-gnome fonts-noto fonts-noto-color-emoji

# Step 3: PipeWire stack
progress 30
apt install -y pipewire pipewire-audio pipewire-pulse wireplumber

# Step 4: Flatpak + Flathub
progress 40
apt install -y flatpak
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# Step 5: Background services
progress 50
apt install -y zram-tools btrfs-progs snapper fwupd power-profiles-daemon
systemctl enable --now fstrim.timer
systemctl enable --now zramswap.service
systemctl enable --now fwupd-refresh.timer
systemctl enable --now snapper-timeline.timer
systemctl enable --now snapper-cleanup.timer

# Step 6: Connectivity
progress 65
apt install -y \
  gnome-online-accounts gnome-shell-extension-gsconnect \
  gvfs-backends gvfs-fuse libmtp-common libmtp-runtime \
  libimobiledevice6 ifuse android-tools-adb android-tools-fastboot

# Step 7: Boot splash (Plymouth)
progress 75
apt install -y plymouth plymouth-themes
plymouth-set-default-theme spinner
sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="[^"]*/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash/' /etc/default/grub
update-grub
update-initramfs -u

# Step 8: Developer Tools (optional)
DEV=$(zenity --list --checklist \
  --title="Optional Developer Tools" \
  --column="Install" --column="Package Group" --column="Description" \
  FALSE "devtools" "Fedora-style developer stack" \
  --width=500 --height=200)

if [[ "$DEV" == *"devtools"* ]]; then
    progress 90
    apt install -y \
      build-essential pkg-config cmake ninja-build \
      autoconf automake libtool gdb valgrind strace \
      python3 python3-pip default-jdk \
      nodejs npm dotnet-sdk-8.0 \
      rustc cargo golang perl ruby \
      podman buildah flatpak-builder
fi

# Step 9: Enable display manager
progress 95
systemctl enable gdm

# Step 10: Cleanup
progress 100
apt autoremove -y
apt clean

info "Nova setup complete!
Reboot now to enjoy your new GNOME-powered system."
