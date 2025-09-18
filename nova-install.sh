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

# Colors and styling for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

# Unicode symbols
CHECK="✓"
CROSS="✗"
ARROW="→"
STAR="★"
DOT="•"
SPINNER=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')

# Ensure running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root${NC}"
   echo "Please run: curl -fsSL <script_url> | sudo bash"
   exit 1
fi

# Function definitions
# Cool terminal UI functions
print_banner() {
    echo -e "${PURPLE}${BOLD}"
    echo "    ███╗   ██╗ ██████╗ ██╗   ██╗ █████╗ "
    echo "    ████╗  ██║██╔═══██╗██║   ██║██╔══██╗"
    echo "    ██╔██╗ ██║██║   ██║██║   ██║███████║"
    echo "    ██║╚██╗██║██║   ██║╚██╗ ██╔╝██╔══██║"
    echo "    ██║ ╚████║╚██████╔╝ ╚████╔╝ ██║  ██║"
    echo "    ╚═╝  ╚═══╝ ╚═════╝   ╚═══╝  ╚═╝  ╚═╝"
    echo -e "${NC}"
    echo -e "${CYAN}${BOLD}    Debian Nova Installer v${SCRIPT_VERSION}${NC}"
    echo -e "${DIM}    Transform your Debian Testing into a modern desktop${NC}"
    echo ""
}

print_step() {
    echo -e "${CYAN}${BOLD}${ARROW} $1${NC}"
}

print_status() {
    echo -e "  ${BLUE}${DOT}${NC} $1"
}

print_success() {
    echo -e "  ${GREEN}${CHECK}${NC} $1"
}

print_warning() {
    echo -e "  ${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "  ${RED}${CROSS}${NC} $1"
}

show_progress() {
    local current=$1
    local total=$2
    local desc="$3"
    local width=50
    local percent=$((current * 100 / total))
    local filled=$((current * width / total))

    printf "\r  ${CYAN}[${NC}"
    for ((i=0; i<filled; i++)); do printf "${GREEN}█${NC}"; done
    for ((i=filled; i<width; i++)); do printf "${DIM}░${NC}"; done
    printf "${CYAN}]${NC} ${BOLD}%3d%%${NC} ${desc}" "$percent"
}

finish_progress() {
    echo ""
}

spinner() {
    local pid=$1
    local msg="$2"
    local i=0

    while kill -0 $pid 2>/dev/null; do
        printf "\r  ${CYAN}${SPINNER[i % ${#SPINNER[@]}]}${NC} %s" "$msg"
        sleep 0.1
        ((i++))
    done
    printf "\r  ${GREEN}${CHECK}${NC} %s\n" "$msg"
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
        echo ""
        echo -e "  ${YELLOW}${BOLD}⚠️  WARNING: This will upgrade your entire system to Debian Testing!${NC}"
        echo -e "  ${DIM}This includes all packages and may take significant time.${NC}"
        echo ""
        echo -e "  ${CYAN}Do you want to continue? ${BOLD}(y/N)${NC}"
        read -p "  > " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_error "Debian Testing is required for Nova. Exiting."
            exit 1
        fi

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
    print_step "Updating System Packages"

    print_status "Refreshing package databases..."
    apt update &>/dev/null &
    spinner $! "Updating package lists"

    print_status "Upgrading installed packages..."
    DEBIAN_FRONTEND=noninteractive apt upgrade -y &>/dev/null &
    spinner $! "Upgrading system packages"

    print_success "System packages updated"
    echo ""
}

# Install bootstrap essentials
install_bootstrap_essentials() {
    print_step "Installing Bootstrap Essentials"

    local BOOTSTRAP_PACKAGES=(
        # Core utilities
        sudo curl wget git git-lfs unzip bash-completion ca-certificates

        # System monitoring and info
        htop fastfetch man-db manpages manpages-dev

        # Archive tools
        tar zip unzip p7zip-full
    )

    local total=${#BOOTSTRAP_PACKAGES[@]}
    local current=0

    for package in "${BOOTSTRAP_PACKAGES[@]}"; do
        ((current++))
        show_progress $current $total "Installing $package"
        DEBIAN_FRONTEND=noninteractive apt install -y $package &>/dev/null
    done
    finish_progress

    # Configure git-lfs if not already done
    if ! git lfs version &>/dev/null; then
        git lfs install --system
    fi

    print_success "Bootstrap essentials installed"
    echo ""
}

# Install GNOME Desktop
install_gnome_desktop() {
    print_step "Installing GNOME Desktop Environment"

    print_status "Installing GNOME core (this may take a while)..."
    DEBIAN_FRONTEND=noninteractive apt install -y gnome-core gdm3 &>/dev/null &
    spinner $! "Installing GNOME core components"

    # Core GNOME apps
    local GNOME_CORE_APPS=(
        nautilus              # Files
        gnome-text-editor      # Text Editor
        gnome-terminal         # Terminal
        gnome-control-center   # Settings
        gnome-calculator       # Calculator
        gnome-screenshot       # Screenshot
        eog                    # Image Viewer
        evince                 # PDF viewer
        gnome-software         # Software center
    )

    local total=${#GNOME_CORE_APPS[@]}
    local current=0
    for app in "${GNOME_CORE_APPS[@]}"; do
        ((current++))
        show_progress $current $total "Installing $(echo $app | cut -d'#' -f1 | xargs)"
        DEBIAN_FRONTEND=noninteractive apt install -y $(echo $app | cut -d'#' -f1 | xargs) &>/dev/null
    done
    finish_progress

    # GNOME extensions and tweaks
    print_status "Installing GNOME extensions and tweaks..."
    local GNOME_EXTENSIONS=(
        gnome-tweaks
        gnome-shell-extensions
        gnome-shell-extension-appindicator
    )
    DEBIAN_FRONTEND=noninteractive apt install -y "${GNOME_EXTENSIONS[@]}" &>/dev/null &
    spinner $! "Installing GNOME extensions"

    # Install GNOME Circle essentials
    print_status "Installing GNOME Circle applications..."
    local GNOME_EXTRAS=(
        gnome-system-monitor
        gnome-disk-utility
        deja-dup
        gnome-software-plugin-flatpak
    )
    DEBIAN_FRONTEND=noninteractive apt install -y "${GNOME_EXTRAS[@]}" &>/dev/null &
    spinner $! "Installing GNOME Circle apps"

    # Enable GDM if not already
    print_status "Enabling GDM display manager..."
    systemctl enable gdm &>/dev/null || true

    # Enable AppIndicator extension for current user (if running via sudo)
    if [[ -n "${SUDO_USER:-}" ]]; then
        sudo -u "$SUDO_USER" dbus-launch gsettings set org.gnome.shell enabled-extensions "['appindicatorsupport@rgcjonas.gmail.com']" 2>/dev/null || true
    fi

    print_success "GNOME desktop environment installed"
    echo ""
}

# Install modern system stack
install_modern_stack() {
    print_step "Installing Modern System Stack"

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
    DEBIAN_FRONTEND=noninteractive apt install -y "${PIPEWIRE_PACKAGES[@]}" &>/dev/null &
    spinner $! "Installing PipeWire audio stack"

    # Ensure PipeWire is the default
    print_status "Configuring PipeWire as default audio system..."
    systemctl --user --global disable pulseaudio.service pulseaudio.socket &>/dev/null || true
    systemctl --user --global enable pipewire pipewire-pulse wireplumber &>/dev/null || true

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
    echo ""
}

# Install connectivity features
install_connectivity() {
    print_step "Installing Connectivity Features"

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
    echo ""
}

# Install polish improvements
install_polish() {
    print_step "Installing System Polish"

    # Plymouth boot splash
    print_status "Installing Plymouth boot splash..."
    DEBIAN_FRONTEND=noninteractive apt install -y plymouth plymouth-themes &>/dev/null &
    spinner $! "Installing Plymouth boot splash"

    # Set spinner theme
    print_status "Configuring Plymouth theme..."
    plymouth-set-default-theme spinner &>/dev/null || true

    # Update GRUB for quiet splash
    print_status "Configuring GRUB for quiet boot..."
    if grep -q "^GRUB_CMDLINE_LINUX_DEFAULT=" /etc/default/grub; then
        sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"/' /etc/default/grub
    else
        echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"' >> /etc/default/grub
    fi

    print_status "Updating GRUB configuration..."
    update-grub &>/dev/null &
    spinner $! "Updating GRUB configuration"

    print_status "Updating initramfs..."
    update-initramfs -u &>/dev/null &
    spinner $! "Rebuilding initramfs"

    # Install kernel headers
    print_status "Installing kernel headers..."
    KERNEL_VERSION=$(uname -r)
    (DEBIAN_FRONTEND=noninteractive apt install -y "linux-headers-${KERNEL_VERSION}" || \
        DEBIAN_FRONTEND=noninteractive apt install -y linux-headers-amd64) &>/dev/null &
    spinner $! "Installing kernel headers"

    print_success "System polish improvements installed"
    echo ""
}

# Install developer tools (optional)
install_developer_tools() {
    print_step "Installing Developer Tools"

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
    echo ""
}

# Setup logging and start
mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE")
exec 2>&1

print_banner
echo -e "${DIM}Started: $(date)${NC}"
echo ""

# Main installation flow
main() {
    echo -e "${DIM}This will transform your Debian system into Nova:${NC}"
    echo -e "  ${CYAN}${DOT}${NC} Minimal GNOME desktop with Wayland"
    echo -e "  ${CYAN}${DOT}${NC} Modern audio stack (PipeWire)"
    echo -e "  ${CYAN}${DOT}${NC} Flatpak app ecosystem"
    echo -e "  ${CYAN}${DOT}${NC} Gaming and development support"
    echo -e "  ${CYAN}${DOT}${NC} Quality-of-life improvements"
    echo ""
    echo -e "${DIM}Estimated time: 15-30 minutes${NC}"
    echo ""
    echo -e "${CYAN}${BOLD}Press Enter to begin installation...${NC}"
    read

    setup_debian_testing
    check_requirements
    update_system
    install_bootstrap_essentials
    install_gnome_desktop
    install_modern_stack
    install_connectivity
    install_polish

    # Ask about developer tools with cool interface
    echo ""
    echo -e "${PURPLE}${BOLD} \u2699  Developer Tools (Optional) \u2699 ${NC}"
    echo ""
    echo -e "  ${CYAN}${BOLD}Available tools:${NC}"
    echo -e "    ${GREEN}${DOT}${NC} Build essentials (gcc, cmake, ninja)"
    echo -e "    ${GREEN}${DOT}${NC} Programming languages (Python, Java, Node.js, Rust, Go)"
    echo -e "    ${GREEN}${DOT}${NC} Container tools (Podman, Buildah)"
    echo -e "    ${GREEN}${DOT}${NC} Debugging tools (gdb, valgrind, strace)"
    echo ""
    echo -e "  ${YELLOW}${BOLD}Install developer tools? ${NC}${BOLD}(y/N)${NC}"
    read -p "  > " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        install_developer_tools
    else
        print_status "Skipping developer tools installation"
        echo ""
    fi

    # Final cleanup
    print_step "Final Cleanup"
    print_status "Removing unnecessary packages..."
    apt autoremove -y &>/dev/null &
    spinner $! "Cleaning up packages"

    print_status "Clearing package cache..."
    apt autoclean &>/dev/null

    # Success message with cool styling
    echo ""
    echo -e "${GREEN}${BOLD}"
    echo "    \u2588\u2588\u2588\u2588\u2588\u2588\u2557 \u2588\u2588\u2557   \u2588\u2588\u2557 \u2588\u2588\u2588\u2588\u2588\u2588\u2557 \u2588\u2588\u2588\u2588\u2588\u2588\u2557 \u2588\u2588\u2588\u2588\u2588\u2588\u2588\u2557\u2588\u2588\u2588\u2588\u2588\u2588\u2588\u2557"
    echo "    \u2588\u2588\u2554\u2550\u2550\u2550\u255d \u2588\u2588\u2551   \u2588\u2588\u2551\u2588\u2588\u2554\u2550\u2550\u2550\u2588\u2588\u2557\u2588\u2588\u2554\u2550\u2550\u2550\u255d\u2588\u2588\u2554\u2550\u2550\u2550\u2550\u255d\u2588\u2588\u2554\u2550\u2550\u2550\u2550\u255d"
    echo "    \u2588\u2588\u2588\u2588\u2588\u2588\u2557 \u2588\u2588\u2551   \u2588\u2588\u2551\u2588\u2588\u2588\u2588\u2588\u2588\u2588\u2551\u2588\u2588\u2588\u2588\u2588\u2588\u2557 \u2588\u2588\u2588\u2588\u2588\u2557  \u2588\u2588\u2588\u2588\u2588\u2557  "
    echo "    \u255a\u2550\u2550\u2550\u2550\u2588\u2588\u2551 \u2588\u2588\u2551   \u2588\u2588\u2551\u2588\u2588\u2554\u2550\u2550\u2588\u2588\u2551\u2588\u2588\u2554\u2550\u2550\u255d \u2588\u2588\u2554\u2550\u2550\u255d  \u2588\u2588\u2554\u2550\u2550\u255d  "
    echo "    \u2588\u2588\u2588\u2588\u2588\u2588\u2554\u255d \u255a\u2588\u2588\u2588\u2588\u2588\u2588\u2554\u255d\u2588\u2588\u2551  \u2588\u2588\u2551\u2588\u2588\u2588\u2588\u2588\u2588\u2557 \u2588\u2588\u2588\u2588\u2588\u2588\u2588\u2557\u2588\u2588\u2588\u2588\u2588\u2588\u2588\u2557"
    echo "    \u255a\u2550\u2550\u2550\u2550\u2550\u255d   \u255a\u2550\u2550\u2550\u2550\u2550\u255d \u255a\u2550\u255d  \u255a\u2550\u255d\u255a\u2550\u2550\u2550\u2550\u2550\u255d \u255a\u2550\u2550\u2550\u2550\u2550\u2550\u255d\u255a\u2550\u2550\u2550\u2550\u2550\u2550\u255d"
    echo -e "${NC}"
    echo ""
    echo -e "${CYAN}${BOLD}    Nova installation completed successfully!${NC}"
    echo ""
    echo -e "${YELLOW}${BOLD}Next steps:${NC}"
    echo -e "  ${GREEN}1.${NC} Reboot your system: ${BOLD}sudo reboot${NC}"
    echo -e "  ${GREEN}2.${NC} Log into GNOME and enjoy your new desktop"
    echo -e "  ${GREEN}3.${NC} Set up GNOME Online Accounts for cloud integration"
    echo -e "  ${GREEN}4.${NC} Install apps from GNOME Software or Flatpak"
    echo ""
    echo -e "${DIM}Installation logs saved to: ${LOG_FILE}${NC}"
    echo ""
    echo -e "${PURPLE}${BOLD}${STAR} Thank you for choosing Nova! ${STAR}${NC}"
    echo ""
    echo -e "${CYAN}Ready to reboot? ${BOLD}(y/N)${NC}"
    read -p "  > " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}${BOLD}Rebooting in 3 seconds...${NC}"
        sleep 3
        reboot
    else
        echo -e "${YELLOW}Remember to reboot when ready: ${BOLD}sudo reboot${NC}"
    fi
}

# Run main function
main "$@"
