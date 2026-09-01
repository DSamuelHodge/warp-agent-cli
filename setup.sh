#!/usr/bin/env bash
#==============================================================================
# Warp Agent CLI Installer for Termux (Android)
#
# This script provisions an Ubuntu PRoot environment inside Termux and
# installs Warp Agent CLI (ARM64) with a direct command launcher.
#==============================================================================
set -euo pipefail

# Color codes for terminal feedback
BOLD='\033[1m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

info() {
  echo -e "${BLUE}${BOLD}[INFO]${NC} $1"
}

success() {
  echo -e "${GREEN}${BOLD}[SUCCESS]${NC} $1"
}

warn() {
  echo -e "${YELLOW}${BOLD}[WARNING]${NC} $1"
}

error() {
  echo -e "${RED}${BOLD}[ERROR]${NC} $1"
  exit 1
}

info "Checking environment compatibility..."

# Verify execution inside Termux
if [ -z "${TERMUX_VERSION:-}" ] && [ ! -d "/data/data/com.termux" ]; then
  error "This script is designed specifically to run inside Termux on Android."
fi

# Verify ARM64 architecture
ARCH=$(uname -m)
if [ "$ARCH" != "aarch64" ] && [ "$ARCH" != "arm64" ]; then
  error "Architecture ($ARCH) not supported. Warp Agent CLI requires an arm64/aarch64 device."
fi

success "Termux ARM64 environment verified!"

info "Updating Termux packages..."
pkg update -y || warn "Failed to update package indices. Attempting to continue..."

info "Installing prerequisite Termux packages (proot-distro, curl)..."
pkg install -y proot-distro curl || error "Failed to install required Termux packages."

info "Checking PRoot Ubuntu installation..."
UBUNTU_ROOTFS="${PREFIX:-/data/data/com.termux/files/usr}/var/lib/proot-distro/installed-rootfs/ubuntu"
if [ -d "$UBUNTU_ROOTFS" ] || proot-distro list 2>/dev/null | grep -qiE 'ubuntu.*(installed|✓)'; then
  info "Ubuntu PRoot container is already installed."
else
  info "Installing Ubuntu PRoot container (this may take a couple of minutes)..."
  proot-distro install ubuntu || error "Failed to install Ubuntu PRoot container."
  success "Ubuntu PRoot container installed successfully."
fi

info "Configuring Ubuntu container and installing Warp Agent CLI..."

# Inline script to run inside the Ubuntu PRoot environment
INSIDE_UBUNTU_SCRIPT=$(cat << 'EOF'
set -e
export DEBIAN_FRONTEND=noninteractive

echo "==> Updating apt repositories inside Ubuntu..."
apt-get update -y && apt-get upgrade -y

echo "==> Installing Ubuntu build and network tools..."
apt-get install -y curl ca-certificates gnupg tar wget sudo

echo "==> Downloading Warp Agent CLI debian package..."
WORK_DIR=$(mktemp -d)
cd "$WORK_DIR"
curl -fSL "https://app.warp.dev/download/agent-cli?format=deb&arch=aarch64" -o warp-cli.deb

echo "==> Installing Warp Agent CLI package..."
dpkg -i warp-cli.deb || apt-get install -f -y

rm -rf "$WORK_DIR"

echo "==> Verification inside Ubuntu..."
if command -v warp >/dev/null 2>&1 || command -v oz >/dev/null 2>&1; then
  echo "Warp CLI installed successfully inside Ubuntu!"
else
  echo "Warning: Binary location not found immediately in standard PATH."
fi
EOF
)

proot-distro login ubuntu -- bash -c "$INSIDE_UBUNTU_SCRIPT" || error "Failed to install Warp CLI inside Ubuntu container."

info "Creating global launcher command in Termux..."
LAUNCHER_PATH="${PREFIX}/bin/warp-agent"
cat << 'EOF' > "$LAUNCHER_PATH"
#!/usr/bin/env bash
# Global shortcut wrapper for Warp Agent CLI inside PRoot Ubuntu
if [ "${1:-}" = "login" ]; then
  echo -e "\033[0;34m[Warp Launcher]\033[0m Starting login flow... Copy any link shown into your browser."
fi
# Pass all arguments directly into the Warp CLI binary inside PRoot
proot-distro login ubuntu -- exec warp "$@"
EOF
chmod +x "$LAUNCHER_PATH"

success "Installation and setup complete!"
echo ""
echo -e "${GREEN}======================================================${NC}"
echo -e "${BOLD}          HOW TO RUN WARP AGENT CLI ON TERMUX${NC}"
echo -e "${GREEN}======================================================${NC}"
echo ""
echo -e "1. Authenticate your account by running:"
echo -e "   ${YELLOW}warp-agent login${NC}"
echo ""
echo -e "2. Launch the agent interactive interface anytime by running:"
echo -e "   ${YELLOW}warp-agent${NC}"
echo ""
echo -e "3. Or login directly into the full Ubuntu shell environment:"
echo -e "   ${YELLOW}proot-distro login ubuntu${NC}"
echo ""
