#!/bin/bash
# Quick test of package availability in Debian Testing

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "Testing package availability in Debian Testing container..."

# Start a simple container
CONTAINER=$(podman run -d debian:testing sleep infinity)

test_package() {
    local pkg=$1
    if podman exec "$CONTAINER" apt-cache show "$pkg" &>/dev/null; then
        echo -e "${GREEN}✓ $pkg${NC}"
        return 0
    else
        echo -e "${RED}✗ $pkg${NC}"
        # Try to find alternatives
        podman exec "$CONTAINER" apt-cache search "^$pkg" 2>/dev/null | head -3
        return 1
    fi
}

# Update package cache
echo "Updating package cache..."
podman exec "$CONTAINER" apt update &>/dev/null

echo -e "\n${YELLOW}Testing iOS packages:${NC}"
test_package "libimobiledevice-1.0-6" || test_package "libimobiledevice6"
test_package "libimobiledevice-utils"
test_package "ifuse"
test_package "usbmuxd"

echo -e "\n${YELLOW}Testing Android packages:${NC}"
test_package "android-tools-adb" || test_package "adb"
test_package "android-tools-fastboot" || test_package "fastboot"
test_package "gnome-shell-extension-gsconnect"

echo -e "\n${YELLOW}Testing GNOME packages:${NC}"
test_package "gnome-core"
test_package "gnome-tweaks"
test_package "gnome-software"

echo -e "\n${YELLOW}Testing System packages:${NC}"
test_package "pipewire"
test_package "wireplumber"
test_package "plymouth"
test_package "fastfetch" || test_package "neofetch"
test_package "fwupd"
test_package "zram-tools"

echo -e "\n${YELLOW}Testing .NET availability:${NC}"
test_package "dotnet-sdk-8.0" || echo "  Will need Microsoft repos for .NET"

# Cleanup
podman stop "$CONTAINER" &>/dev/null
podman rm "$CONTAINER" &>/dev/null

echo -e "\n${GREEN}Test complete!${NC}"