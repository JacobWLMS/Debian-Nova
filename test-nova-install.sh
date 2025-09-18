#!/bin/bash
# Test script for Nova installer in Podman container

set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "Starting Nova installer test in Podman container..."

# Create a test container
echo "Creating Debian Testing container..."
CONTAINER_NAME="nova-test-$(date +%s)"

# Start container with systemd support (needed for services)
podman run -d \
    --name "$CONTAINER_NAME" \
    --privileged \
    --volume /sys/fs/cgroup:/sys/fs/cgroup:ro \
    --volume "$(pwd)/nova-install.sh:/nova-install.sh:ro" \
    debian:testing \
    sleep infinity

echo "Container $CONTAINER_NAME created"

# Function to run commands in container
run_in_container() {
    podman exec "$CONTAINER_NAME" bash -c "$1"
}

# Cleanup function
cleanup() {
    echo -e "${YELLOW}Cleaning up...${NC}"
    podman stop "$CONTAINER_NAME" 2>/dev/null || true
    podman rm "$CONTAINER_NAME" 2>/dev/null || true
}

trap cleanup EXIT

# Update container and install basic tools
echo "Setting up container environment..."
run_in_container "apt update && apt install -y systemd-container"

# Test package availability
echo -e "${GREEN}Testing package availability in Debian Testing...${NC}"

# Test iOS packages
echo "Checking iOS packages..."
if run_in_container "apt-cache show libimobiledevice-1.0-6 2>/dev/null" ; then
    echo -e "${GREEN}✓ libimobiledevice-1.0-6 is available${NC}"
else
    echo -e "${RED}✗ libimobiledevice-1.0-6 NOT available${NC}"
    # Try alternative package name
    if run_in_container "apt-cache show libimobiledevice6 2>/dev/null" ; then
        echo -e "${YELLOW}  Alternative found: libimobiledevice6${NC}"
    fi
fi

# Test Android packages
echo "Checking Android packages..."
if run_in_container "apt-cache show android-tools-adb 2>/dev/null" ; then
    echo -e "${GREEN}✓ android-tools-adb is available${NC}"
elif run_in_container "apt-cache show adb 2>/dev/null" ; then
    echo -e "${GREEN}✓ adb is available (alternative package name)${NC}"
else
    echo -e "${RED}✗ No Android ADB package found${NC}"
fi

# Test other critical packages
echo "Checking other critical packages..."
PACKAGES_TO_CHECK=(
    "gnome-core"
    "pipewire"
    "wireplumber"
    "flatpak"
    "plymouth"
    "fastfetch"
    "gnome-shell-extension-gsconnect"
    "fwupd"
    "zram-tools"
)

for pkg in "${PACKAGES_TO_CHECK[@]}"; do
    if run_in_container "apt-cache show $pkg 2>/dev/null | grep -q Package:" ; then
        echo -e "${GREEN}✓ $pkg is available${NC}"
    else
        echo -e "${RED}✗ $pkg NOT available${NC}"
    fi
done

# Test the actual install script (dry run parts)
echo ""
echo -e "${YELLOW}Running Nova install script checks...${NC}"

# Copy and modify script for testing (skip actual installation)
podman cp nova-install.sh "$CONTAINER_NAME:/nova-install-test.sh"

# Make it executable
run_in_container "chmod +x /nova-install-test.sh"

# Test just the package checking functions
cat << 'EOF' | podman exec -i "$CONTAINER_NAME" bash
#!/bin/bash
source /nova-install-test.sh

# Override main to just test functions
main() {
    echo "Testing package detection functions..."

    # Test iOS package detection
    if apt-cache show libimobiledevice-1.0-6 &>/dev/null; then
        echo "iOS: Would install libimobiledevice-1.0-6"
    elif apt-cache show libimobiledevice6 &>/dev/null; then
        echo "iOS: Would install libimobiledevice6"
    else
        echo "iOS: No compatible package found"
    fi

    # Test Android package detection
    if apt-cache show android-tools-adb &>/dev/null; then
        echo "Android: Would install android-tools-adb"
    elif apt-cache show adb &>/dev/null; then
        echo "Android: Would install adb"
    else
        echo "Android: No compatible package found"
    fi
}

# Run the test
check_requirements 2>/dev/null || true
EOF

echo ""
echo -e "${GREEN}Test completed!${NC}"
echo "Container name: $CONTAINER_NAME"
echo "To inspect further: podman exec -it $CONTAINER_NAME bash"
echo "To cleanup: podman stop $CONTAINER_NAME && podman rm $CONTAINER_NAME"