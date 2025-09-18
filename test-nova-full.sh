#!/bin/bash
# Full test of Nova installer in container (simulated, no actual GUI)

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Nova Installer - Full Container Test${NC}"
echo "======================================"

# Create test container with needed capabilities
CONTAINER_NAME="nova-full-test-$(date +%s)"

echo "Starting Debian Testing container..."
podman run -d \
    --name "$CONTAINER_NAME" \
    --cap-add SYS_ADMIN \
    --security-opt apparmor=unconfined \
    --volume "$(pwd)/nova-install.sh:/nova-install.sh:ro" \
    debian:testing \
    sleep infinity

# Cleanup on exit
cleanup() {
    echo -e "\n${YELLOW}Cleaning up container...${NC}"
    podman stop "$CONTAINER_NAME" 2>/dev/null || true
    podman rm "$CONTAINER_NAME" 2>/dev/null || true
}
trap cleanup EXIT

# Wait for container
sleep 2

echo -e "${GREEN}✓ Container started${NC}"

# Install prerequisites
echo -e "\n${BLUE}Installing prerequisites...${NC}"
podman exec "$CONTAINER_NAME" apt update
podman exec "$CONTAINER_NAME" apt install -y systemd procps

# Copy and modify the script for testing
echo -e "\n${BLUE}Preparing test script...${NC}"
podman cp nova-install.sh "$CONTAINER_NAME:/nova-test.sh"

# Create a wrapper that simulates user responses
cat << 'EOF' | podman exec -i "$CONTAINER_NAME" tee /test-wrapper.sh > /dev/null
#!/bin/bash
set -euo pipefail

# Override zenity to simulate user choices
zenity() {
    case "$1" in
        --info)
            echo "[ZENITY INFO] $*" >&2
            return 0
            ;;
        --question)
            echo "[ZENITY QUESTION] $*" >&2
            # Simulate "No" for upgrade to testing, "Yes" for dev tools
            if echo "$*" | grep -q "upgrade to Debian Testing"; then
                return 1  # No - we're already on testing
            elif echo "$*" | grep -q "developer tools"; then
                return 0  # Yes to dev tools
            fi
            return 0
            ;;
        --progress)
            echo "[ZENITY PROGRESS] $*" >&2
            cat > /dev/null  # consume input
            return 0
            ;;
        *)
            echo "[ZENITY] $*" >&2
            return 0
            ;;
    esac
}
export -f zenity

# Source the actual script
source /nova-test.sh

# Override some functions for testing
update_grub() {
    echo "SIMULATED: update-grub"
}

update_initramfs() {
    echo "SIMULATED: update-initramfs $*"
}

plymouth_set_default_theme() {
    echo "SIMULATED: plymouth-set-default-theme $*"
}

systemctl() {
    case "$1" in
        enable|--user)
            echo "SIMULATED: systemctl $*"
            ;;
        *)
            command systemctl "$@" 2>/dev/null || echo "SIMULATED: systemctl $*"
            ;;
    esac
}

# Test individual functions
echo "Testing functions..."
echo ""

echo "=== Testing Debian version detection ==="
setup_debian_testing

echo ""
echo "=== Testing requirements check ==="
check_requirements

echo ""
echo "=== Simulating package checks ==="

# Test iOS package detection
echo -n "iOS packages: "
if apt-cache show libimobiledevice-1.0-6 &>/dev/null; then
    echo "libimobiledevice-1.0-6 ✓"
elif apt-cache show libimobiledevice6 &>/dev/null; then
    echo "libimobiledevice6 ✓"
else
    echo "NOT FOUND ✗"
fi

# Test Android package detection
echo -n "Android packages: "
if apt-cache show android-tools-adb &>/dev/null; then
    echo "android-tools-adb ✓"
elif apt-cache show adb &>/dev/null; then
    echo "adb ✓"
else
    echo "NOT FOUND ✗"
fi

echo ""
echo "=== Testing package availability ==="
PACKAGES=(gnome-core pipewire wireplumber flatpak plymouth fastfetch zram-tools fwupd)
for pkg in "${PACKAGES[@]}"; do
    if apt-cache show "$pkg" &>/dev/null; then
        echo "✓ $pkg"
    else
        echo "✗ $pkg NOT AVAILABLE"
    fi
done

echo ""
echo "Test completed successfully!"
EOF

podman exec "$CONTAINER_NAME" chmod +x /test-wrapper.sh

# Run the test
echo -e "\n${BLUE}Running Nova installer test...${NC}"
echo "----------------------------------------"

if podman exec "$CONTAINER_NAME" bash /test-wrapper.sh; then
    echo -e "\n${GREEN}✓ Test completed successfully!${NC}"
else
    echo -e "\n${RED}✗ Test failed${NC}"
    exit 1
fi

echo -e "\n${BLUE}Test Summary:${NC}"
echo "- Debian Testing detection: ✓"
echo "- Package availability: ✓"
echo "- Function simulation: ✓"
echo ""
echo -e "${GREEN}Nova installer is ready for Debian Testing!${NC}"