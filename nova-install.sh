#!/bin/bash
set -euo pipefail

# --- Zenity helper ---
info() { zenity --info --width=400 --title="Nova Installer" --text="$1"; }
progress() { zenity --progress --title="Nova Installer" --percentage="$1" --auto-close; }

info "Welcome to Nova Setup!
This will configure your Debian Testing system into Nova.
All software comes from GNOME Core or GNOME Circle.
Background tweaks will run silently."

# Step 1: System update
progress 5
apt update && apt full-upgrade -y

# Step 2: Core GNOME desktop
progress 15
apt install -y \
  gnome-core gdm3 gnome-control-center nautilus \
  gnome-terminal gnome-software gnome-software-plugin-flatpak \
  gnome-system-monitor gnome-tweaks gnome-disk-utility \
  deja-dup xdg-desktop-portal-gnome fonts-noto fonts-noto-color-emoji

# Step 3: PipeWire audio
progress 30
apt install -y pipewire pipewire-audio pipewire-pulse wireplumber

# Step 4: Flatpak + Flathub
progress 40
apt install -y flatpak
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# Step 5: Background services (no GUI, invisible)
progress 50
apt install -y zram-tools btrfs-progs snapper fwupd power-profiles-daemon
systemctl enable --now fstrim.timer
systemctl enable --now zramswap.service
systemctl enable --now fwupd-refresh.timer
systemctl enable --now snapper-timeline.timer
systemctl enable --now snapper-cleanup.timer

# Step 6: Connectivity
progress 65
apt install -y gnome-online-accounts gnome-shell-extension-gsconnect \
  gvfs-backends gvfs-fuse libmtp-common libmtp-runtime \
  libimobiledevice6 ifuse android-tools-adb android-tools-fastboot

# Step 7: Optional GNOME Circle apps (user choice)
CIRCLE=$(zenity --list --checklist \
  --title="Optional GNOME Circle Apps" \
  --column="Install" --column="App" --column="Description" \
  FALSE "amberol" "Lightweight music player" \
  FALSE "loupe" "Modern GNOME image viewer" \
  FALSE "snapshot" "Simple camera app" \
  FALSE "gnome-clocks" "World clock, timers" \
  --width=500 --height=300)

if [[ -n "$CIRCLE" ]]; then
    apt install -y $CIRCLE
fi

# Step 8: Enable display manager
progress 85
systemctl enable gdm

# Final
progress 100
info "Nova setup complete!
Reboot now to start using your new GNOME-powered system."
