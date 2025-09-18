#!/bin/bash
#
# Nova Install Script for Debian Testing
# Transforms a fresh Debian Testing installation into Nova
#
# Usage: curl -fsSL https://example.com/nova-install.sh | bash
#
# Features:
# - Idempotent (safe to re-run)
# - Minimal and focused on quality-of-life improvements
# - Modern Fedora-like desktop experience
# - Optional developer tools
#

set -euo pipefail

# Script configuration
SCRIPT_VERSION="1.0.0"
LOG_FILE="/var/log/nova-install.log"
TEMP_DIR="/tmp/nova-install-$$"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Ensure running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root${NC}"
   echo "Please run: curl -fsSL <script_url> | sudo bash"
   exit 1
fi

# Function definitions
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Cleanup function
cleanup() {
    if [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
}

trap cleanup EXIT

# Configure Debian Testing repositories
setup_debian_testing() {
    print_status "Configuring Debian Testing repositories..."

    # Check current Debian version - include trixie (current testing codename)
    # Check both old sources.list format and new DEB822 .sources format
    if ! (grep -qE "testing|trixie|sid" /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null || \
          grep -qE "Suites:.*testing|Suites:.*trixie|Suites:.*sid" /etc/apt/sources.list.d/*.sources 2>/dev/null); then
        print_warning "System is not running Debian Testing/Trixie"

        echo ""
        print_warning "This system is not running Debian Testing/Trixie"
        print_status "Upgrading system to Debian Testing..."

        # Backup current sources.list
        cp /etc/apt/sources.list /etc/apt/sources.list.backup.$(date +%Y%m%d_%H%M%S)

        # Configure Debian Testing repositories
        cat > /etc/apt/sources.list <<EOF
deb http://deb.debian.org/debian/ testing main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian/ testing main contrib non-free non-free-firmware

deb http://security.debian.org/debian-security testing-security main contrib non-free non-free-firmware
deb-src http://security.debian.org/debian-security testing-security main contrib non-free non-free-firmware

deb http://deb.debian.org/debian/ testing-updates main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian/ testing-updates main contrib non-free non-free-firmware
EOF

        print_status "Upgrading to Debian Testing..."
        apt update
        DEBIAN_FRONTEND=noninteractive apt full-upgrade -y

        print_success "System upgraded to Debian Testing"
    else
        print_success "System is already running Debian Testing/Trixie"
    fi
}

# Check system requirements
check_requirements() {
    print_status "Checking system requirements..."

    # Check for internet connection (try multiple methods)
    if ! ping -c 1 -W 2 debian.org &>/dev/null && ! curl -s --head http://deb.debian.org &>/dev/null; then
        print_error "No internet connection detected"
        exit 1
    fi

    # Check disk space (need at least 5GB)
    AVAILABLE_SPACE=$(df / | awk 'NR==2 {print $4}')
    if [[ $AVAILABLE_SPACE -lt 5242880 ]]; then
        print_error "Insufficient disk space. At least 5GB required."
        exit 1
    fi

    print_success "System requirements check passed"
}

# Update system
update_system() {
    print_status "Updating package lists..."
    apt update

    print_status "Upgrading existing packages..."
    DEBIAN_FRONTEND=noninteractive apt upgrade -y

    print_success "System updated"
}

# Install bootstrap essentials
install_bootstrap_essentials() {
    print_status "Installing bootstrap essentials..."

    local BOOTSTRAP_PACKAGES=(
        # Core utilities
        sudo curl wget git git-lfs unzip bash-completion ca-certificates

        # System monitoring and info
        htop fastfetch man-db manpages manpages-dev

        # Archive tools
        tar zip unzip p7zip-full
    )

    DEBIAN_FRONTEND=noninteractive apt install -y "${BOOTSTRAP_PACKAGES[@]}"

    # Configure git-lfs if not already done
    if ! git lfs version &>/dev/null; then
        git lfs install --system
    fi

    print_success "Bootstrap essentials installed"
}

# Install GNOME Desktop
install_gnome_desktop() {
    print_status "Installing GNOME desktop environment..."

    # Install core GNOME (minimal)
    DEBIAN_FRONTEND=noninteractive apt install -y gnome-core gdm3

    # Core GNOME apps
    local GNOME_CORE_APPS=(
        nautilus
        gnome-text-editor
        gnome-terminal
        gnome-control-center
        gnome-calculator
        gnome-screenshot
        eog
        evince
        gnome-software
    )
    DEBIAN_FRONTEND=noninteractive apt install -y "${GNOME_CORE_APPS[@]}"

    # GNOME extensions and tweaks
    local GNOME_EXTENSIONS=(
        gnome-tweaks
        gnome-shell-extensions
        gnome-shell-extension-appindicator
    )
    DEBIAN_FRONTEND=noninteractive apt install -y "${GNOME_EXTENSIONS[@]}"

    # Install GNOME Circle essentials
    local GNOME_EXTRAS=(
        gnome-system-monitor
        gnome-disk-utility
        deja-dup
        gnome-software-plugin-flatpak
    )
    DEBIAN_FRONTEND=noninteractive apt install -y "${GNOME_EXTRAS[@]}"

    # Enable GDM if not already
    systemctl enable gdm || true

    # Enable AppIndicator extension for current user (if running via sudo)
    if [[ -n "${SUDO_USER:-}" ]]; then
        sudo -u "$SUDO_USER" dbus-launch gsettings set org.gnome.shell enabled-extensions "['appindicatorsupport@rgcjonas.gmail.com']" 2>/dev/null || true
    fi

    print_success "GNOME desktop installed"
}

# Install modern system stack
install_modern_stack() {
    print_status "Installing modern system stack..."

    # PipeWire audio stack
    print_status "Installing PipeWire audio system..."
    local PIPEWIRE_PACKAGES=(
        pipewire
        pipewire-audio-client-libraries
        pipewire-pulse
        pipewire-alsa
        pipewire-jack
        wireplumber
        libspa-0.2-bluetooth
        libspa-0.2-jack
    )
    DEBIAN_FRONTEND=noninteractive apt install -y "${PIPEWIRE_PACKAGES[@]}"

    # Ensure PipeWire is the default
    systemctl --user --global disable pulseaudio.service pulseaudio.socket || true
    systemctl --user --global enable pipewire pipewire-pulse wireplumber || true

    # Flatpak setup
    print_status "Setting up Flatpak..."
    DEBIAN_FRONTEND=noninteractive apt install -y flatpak

    # Add Flathub if not already added
    if ! flatpak remote-list | grep -q flathub; then
        flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    fi

    # Firmware updates
    print_status "Installing firmware update tools..."
    DEBIAN_FRONTEND=noninteractive apt install -y fwupd
    systemctl enable fwupd-refresh.timer || true

    # Performance optimizations and system stability
    print_status "Installing performance optimization tools..."
    DEBIAN_FRONTEND=noninteractive apt install -y zram-tools power-profiles-daemon gamemode

    # Enable systemd-oomd for memory pressure handling
    systemctl enable systemd-oomd || true

    # Enable multiarch for 32-bit library support (gaming)
    dpkg --add-architecture i386 || true

    # Configure zram
    if [[ ! -f /etc/default/zramswap ]]; then
        cat > /etc/default/zramswap <<EOF
# Percentage of RAM to use for zram
PERCENTAGE=50

# Priority of zram swap
PRIORITY=100
EOF
    fi

    systemctl enable zramswap || true

    # Enable fstrim for SSDs
    systemctl enable fstrim.timer || true

    # Btrfs snapshots (if filesystem is btrfs)
    if findmnt -n -o FSTYPE / | grep -q btrfs; then
        print_status "Detected Btrfs filesystem, installing snapshot tools..."
        DEBIAN_FRONTEND=noninteractive apt install -y btrfs-progs snapper

        # Configure snapper if not already done
        if [[ ! -f /etc/snapper/configs/root ]]; then
            snapper -c root create-config /
            systemctl enable snapper-timeline.timer snapper-cleanup.timer || true
        fi
    fi

    # Firewall setup
    print_status "Configuring firewall..."
    DEBIAN_FRONTEND=noninteractive apt install -y ufw
    ufw --force enable
    ufw default deny incoming
    ufw default allow outgoing

    # Gaming support (underlying only)
    print_status "Installing gaming support libraries..."
    local GAMING_PACKAGES=(
        mesa-vulkan-drivers
        mesa-utils
        vulkan-tools
    )
    DEBIAN_FRONTEND=noninteractive apt install -y "${GAMING_PACKAGES[@]}"

    # Power management
    print_status "Installing power management tools..."
    DEBIAN_FRONTEND=noninteractive apt install -y powertop

    print_success "Modern system stack installed"
}

# Install connectivity features
install_connectivity() {
    print_status "Installing connectivity features..."

    # GNOME Online Accounts
    DEBIAN_FRONTEND=noninteractive apt install -y gnome-online-accounts

    # Networking and VPN support
    print_status "Installing networking and VPN tools..."
    local NETWORK_PACKAGES=(
        openssh-client
        openvpn
        wireguard-tools
        network-manager-openvpn
        network-manager-openvpn-gnome
        network-manager-vpnc
        network-manager-vpnc-gnome
        avahi-daemon
        gnome-remote-desktop
    )
    DEBIAN_FRONTEND=noninteractive apt install -y "${NETWORK_PACKAGES[@]}"

    # Android support
    print_status "Installing Android device support..."
    local ANDROID_PACKAGES=(
        gnome-shell-extension-gsconnect
        libmtp-runtime
        mtp-tools
    )

    # Check for android-tools-adb vs adb package names
    if apt-cache show android-tools-adb &>/dev/null; then
        ANDROID_PACKAGES+=(android-tools-adb android-tools-fastboot)
    elif apt-cache show adb &>/dev/null; then
        ANDROID_PACKAGES+=(adb fastboot)
    fi

    DEBIAN_FRONTEND=noninteractive apt install -y "${ANDROID_PACKAGES[@]}" || print_warning "Some Android packages failed to install"

    # iOS support
    print_status "Installing iOS device support..."

    # Check which libimobiledevice package is available
    if apt-cache show libimobiledevice-1.0-6 &>/dev/null; then
        LIBIMOBILE_PKG="libimobiledevice-1.0-6"
    elif apt-cache show libimobiledevice6 &>/dev/null; then
        LIBIMOBILE_PKG="libimobiledevice6"
    else
        print_warning "libimobiledevice package not found, skipping iOS support"
        return
    fi

    local IOS_PACKAGES=(
        "$LIBIMOBILE_PKG"
        libimobiledevice-utils
        ifuse
        usbmuxd
    )
    DEBIAN_FRONTEND=noninteractive apt install -y "${IOS_PACKAGES[@]}" || print_warning "Some iOS packages failed to install"

    # Add current user to necessary groups for device access
    if [[ -n "${SUDO_USER:-}" ]]; then
        usermod -a -G plugdev "${SUDO_USER}" || true
    fi

    print_success "Connectivity features installed"
}

# Install polish improvements
install_polish() {
    print_status "Installing system polish improvements..."

    # Plymouth boot splash
    print_status "Installing Plymouth boot splash..."
    DEBIAN_FRONTEND=noninteractive apt install -y plymouth plymouth-themes

    # Set spinner theme
    plymouth-set-default-theme spinner || true

    # Update GRUB for quiet splash
    if grep -q "^GRUB_CMDLINE_LINUX_DEFAULT=" /etc/default/grub; then
        sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"/' /etc/default/grub
    else
        echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"' >> /etc/default/grub
    fi

    update-grub
    update-initramfs -u

    # Install kernel headers
    print_status "Installing kernel headers..."
    KERNEL_VERSION=$(uname -r)
    DEBIAN_FRONTEND=noninteractive apt install -y "linux-headers-${KERNEL_VERSION}" || \
        DEBIAN_FRONTEND=noninteractive apt install -y linux-headers-amd64

    print_success "System polish improvements installed"
}

# Install developer tools (optional)
install_developer_tools() {
    print_status "Installing developer tools..."

    # Core build tools
    local BUILD_TOOLS=(
        build-essential
        pkg-config
        cmake
        ninja-build
        autoconf
        automake
        libtool
        gdb
        valgrind
        strace
    )

    # Programming languages (preinstalled in your spec)
    local LANGUAGES=(
        python3
        python3-pip
        default-jdk
        nodejs
        npm
        rustc
        cargo
        golang
        perl
        ruby
    )

    # Containers and packaging
    local CONTAINERS=(
        podman
        buildah
        flatpak-builder
    )

    print_status "Installing build tools..."
    DEBIAN_FRONTEND=noninteractive apt install -y "${BUILD_TOOLS[@]}"

    print_status "Installing programming languages..."
    DEBIAN_FRONTEND=noninteractive apt install -y "${LANGUAGES[@]}"

    print_status "Installing container tools..."
    DEBIAN_FRONTEND=noninteractive apt install -y "${CONTAINERS[@]}"

    print_success "Developer tools installed"
}

# Setup logging
mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE")
exec 2>&1

echo "=================================================================================="
echo " Nova Installer v${SCRIPT_VERSION} - $(date)"
echo "=================================================================================="
echo ""

# Main installation flow
main() {
    echo "Nova Installer - Transforming Debian Testing into Nova"
    echo "Installing: GNOME desktop, PipeWire, Flatpak, gaming support, developer tools"
    echo "Estimated time: 15-30 minutes"
    echo ""
    setup_debian_testing
    check_requirements
    update_system
    install_bootstrap_essentials
    install_gnome_desktop
    install_modern_stack
    install_connectivity
    install_polish

    # Install developer tools (always)
    install_developer_tools

    # Final cleanup
    print_status "Cleaning up..."
    apt autoremove -y
    apt autoclean

    # Success message
    echo ""
    echo "=================================================================================="
    print_success "Nova installation completed successfully!"
    echo "=================================================================================="
    echo ""
    echo "Next steps:"
    echo "  1. Reboot your system to ensure all services start correctly"
    echo "  2. Log into GNOME and configure your preferences"
    echo "  3. Set up GNOME Online Accounts for cloud integration"
    echo "  4. Install additional software from GNOME Software or Flatpak"
    echo ""
    echo "Logs saved to: ${LOG_FILE}"
    echo ""
    print_status "Installation complete. Please reboot your system: sudo reboot"
}

# Run main function
main "$@"