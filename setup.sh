#!/usr/bin/env bash
#==============================================================================
# Warp Agent CLI Installer for Termux (Android)
#
# Provisions Ubuntu PRoot, installs Warp Agent CLI (ARM64), Tailcat, and a
# Termux:API bridge so the agent can call on-device APIs.
#==============================================================================
set -euo pipefail

BOLD='\033[1m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info() { echo -e "${BLUE}${BOLD}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}${BOLD}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}${BOLD}[WARNING]${NC} $1"; }
error() { echo -e "${RED}${BOLD}[ERROR]${NC} $1"; exit 1; }

info "Checking environment compatibility..."

if [ -z "${TERMUX_VERSION:-}" ] && [ ! -d "/data/data/com.termux" ]; then
  error "This script is designed specifically to run inside Termux on Android."
fi

ARCH=$(uname -m)
if [ "$ARCH" != "aarch64" ] && [ "$ARCH" != "arm64" ]; then
  error "Architecture ($ARCH) not supported. Warp Agent CLI requires an arm64/aarch64 device."
fi

success "Termux ARM64 environment verified!"

pkg_ok() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

termux_api_app_ok() {
  [ -d "/data/data/com.termux.api" ] && return 0
  command -v cmd >/dev/null 2>&1 && cmd package list packages 2>/dev/null | grep -q "package:com.termux.api" && return 0
  [ -x /system/bin/pm ] && /system/bin/pm list packages 2>/dev/null | grep -q "package:com.termux.api" && return 0
  return 1
}

NEED_PKG=()
for p in proot-distro curl termux-api; do
  if pkg_ok "$p"; then
    info "$p already installed."
  else
    NEED_PKG+=("$p")
  fi
done

if [ "${#NEED_PKG[@]}" -gt 0 ]; then
  info "Updating Termux packages..."
  pkg update -y || warn "Failed to update package indices. Attempting to continue..."
  info "Installing missing Termux packages: ${NEED_PKG[*]}"
  pkg install -y "${NEED_PKG[@]}" || error "Failed to install required Termux packages."
else
  info "Termux packages already present (proot-distro, curl, termux-api)."
fi

if ! command -v termux-battery-status >/dev/null 2>&1; then
  warn "termux-api CLI helpers are missing from PATH."
fi

if termux_api_app_ok; then
  success "Termux:API Android app is installed."
else
  warn "Termux:API Android app is not installed. CLI package alone is not enough."
  warn "Install it from F-Droid: https://f-droid.org/packages/com.termux.api/"
  warn "or GitHub: https://github.com/termux/termux-api/releases"
fi

info "Checking PRoot Ubuntu installation..."
UBUNTU_ROOTFS="${PREFIX:-/data/data/com.termux/files/usr}/var/lib/proot-distro/installed-rootfs/ubuntu"
if [ -d "$UBUNTU_ROOTFS" ] || proot-distro list 2>/dev/null | grep -qiE 'ubuntu.*(installed|✓)'; then
  info "Ubuntu PRoot container is already installed."
else
  info "Installing Ubuntu PRoot container (this may take a couple of minutes)..."
  proot-distro install ubuntu || error "Failed to install Ubuntu PRoot container."
  success "Ubuntu PRoot container installed successfully."
fi

BRIDGE_DIR="${HOME}/.warp-termux-api"
mkdir -p "${BRIDGE_DIR}/queue"

info "Configuring Ubuntu container (Warp Agent CLI + Tailcat + API wrappers)..."

INSIDE_UBUNTU_SCRIPT=$(cat << 'UBUNTU_EOF'
set -e
export DEBIAN_FRONTEND=noninteractive

echo "==> Updating apt repositories inside Ubuntu..."
apt-get update -y && apt-get upgrade -y

echo "==> Installing Ubuntu tools..."
apt-get install -y curl ca-certificates gnupg tar wget sudo python3

if command -v warp >/dev/null 2>&1 || command -v oz >/dev/null 2>&1; then
  echo "==> Warp Agent CLI already installed. Skipping download."
else
  WORK_DIR=$(mktemp -d)
  cd "$WORK_DIR"
  echo "==> Downloading Warp Agent CLI debian package..."
  curl -fSL "https://app.warp.dev/download/agent-cli?format=deb&arch=aarch64" -o warp-cli.deb
  echo "==> Installing Warp Agent CLI package..."
  dpkg -i warp-cli.deb || apt-get install -f -y
  rm -rf "$WORK_DIR"
fi

if command -v tailcat >/dev/null 2>&1; then
  echo "==> Tailcat already installed. Skipping download."
  tailcat version 2>/dev/null || true
else
  WORK_DIR=$(mktemp -d)
  cd "$WORK_DIR"
  echo "==> Downloading Tailcat linux arm64 package..."
  TAILCAT_DEB_URL=$(python3 - << 'PY'
import json, urllib.request
req = urllib.request.Request(
    "https://api.github.com/repos/tailscale/tailcat/releases/latest",
    headers={"User-Agent": "warp-agent-cli-termux"},
)
with urllib.request.urlopen(req, timeout=30) as resp:
    data = json.load(resp)
for asset in data.get("assets", []):
    name = asset.get("name") or ""
    if name.endswith("_linux_arm64.deb"):
        print(asset["browser_download_url"])
        break
else:
    raise SystemExit("no linux_arm64.deb in latest Tailcat release")
PY
)
  curl -fSL "$TAILCAT_DEB_URL" -o tailcat.deb
  echo "==> Installing Tailcat package..."
  dpkg -i tailcat.deb || apt-get install -f -y
  rm -rf "$WORK_DIR"
fi

echo "==> Installing Termux:API client wrapper for Warp..."
cat > /usr/local/bin/termux-api << 'WRAP'
#!/usr/bin/env bash
set -euo pipefail
BRIDGE="${WARP_TERMUX_API_BRIDGE:-/bridge}"
QUEUE="${BRIDGE}/queue"

if [ $# -lt 1 ]; then
  echo "Usage: termux-api <command> [args...]" >&2
  echo "Example: termux-api battery-status" >&2
  echo "         termux-api toast -- \"hello\"" >&2
  exit 2
fi

CMD="$1"
shift
case "$CMD" in
  termux-*) ;;
  *) CMD="termux-${CMD}" ;;
esac

if [ ! -d "$QUEUE" ]; then
  echo "Termux:API bridge is not mounted at ${BRIDGE}." >&2
  echo "Start Warp with the warp-agent launcher so /bridge is bound." >&2
  exit 1
fi

ID="$(date +%s%N)-$$"
REQ="${QUEUE}/${ID}.req"
{
  printf '%s\n' "$CMD"
  printf '%s\n' "$@"
} > "$REQ"

for _ in $(seq 1 300); do
  if [ -f "${QUEUE}/${ID}.done" ]; then
    [ -f "${QUEUE}/${ID}.out" ] && cat "${QUEUE}/${ID}.out"
    [ -f "${QUEUE}/${ID}.err" ] && cat "${QUEUE}/${ID}.err" >&2
    RC=0
    [ -f "${QUEUE}/${ID}.rc" ] && RC="$(cat "${QUEUE}/${ID}.rc")"
    rm -f "$REQ" "${QUEUE}/${ID}.out" "${QUEUE}/${ID}.err" "${QUEUE}/${ID}.rc" "${QUEUE}/${ID}.done"
    exit "${RC:-0}"
  fi
  sleep 0.1
done

echo "Timed out waiting for Termux:API bridge (${CMD}). Is warp-termux-api-bridge running?" >&2
rm -f "$REQ" "${QUEUE}/${ID}.out" "${QUEUE}/${ID}.err" "${QUEUE}/${ID}.rc" "${QUEUE}/${ID}.done"
exit 124
WRAP
chmod +x /usr/local/bin/termux-api

for helper in \
  battery-status brightness camera-info camera-photo clipboard-get clipboard-set \
  contact-list dialog download fingerprint location media-player media-scan \
  microphone-record notification notification-remove sensor share sms-list sms-send \
  speech-to-text storage-get telephony-call telephony-cellinfo telephony-deviceinfo \
  toast torch tts-engines tts-speak usb vibrate volume wallpaper \
  wifi-connectioninfo wifi-enable wifi-scaninfo wake-lock wake-unlock
do
  printf '#!/usr/bin/env bash\nexec /usr/local/bin/termux-api %s "$@"\n' "$helper" > "/usr/local/bin/termux-${helper}"
  chmod +x "/usr/local/bin/termux-${helper}"
done

echo "==> Verification inside Ubuntu..."
if command -v warp >/dev/null 2>&1 || command -v oz >/dev/null 2>&1; then
  echo "Warp CLI installed successfully inside Ubuntu!"
else
  echo "Warning: Warp binary not found immediately in standard PATH."
fi
if command -v tailcat >/dev/null 2>&1; then
  echo "Tailcat installed successfully inside Ubuntu!"
  tailcat version 2>/dev/null || true
else
  echo "Warning: tailcat not found in PATH."
fi
UBUNTU_EOF
)

proot-distro login ubuntu -- bash -c "$INSIDE_UBUNTU_SCRIPT" || error "Failed to install packages inside Ubuntu container."

info "Creating Termux:API bridge daemon..."
cat << 'EOF' > "${PREFIX}/bin/warp-termux-api-bridge"
#!/usr/bin/env bash
# Executes allowlisted Termux:API commands on the host for Warp inside PRoot.
set -euo pipefail
BRIDGE="${WARP_TERMUX_API_BRIDGE:-$HOME/.warp-termux-api}"
QUEUE="${BRIDGE}/queue"
mkdir -p "$QUEUE"

allowed() {
  case "$1" in
    termux-battery-status|termux-brightness|termux-camera-info|termux-camera-photo|\
    termux-clipboard-get|termux-clipboard-set|termux-contact-list|termux-dialog|\
    termux-download|termux-fingerprint|termux-infrared-frequencies|termux-infrared-transmit|\
    termux-job-scheduler|termux-location|termux-media-player|termux-media-scan|\
    termux-microphone-record|termux-nfc|termux-notification|termux-notification-remove|\
    termux-sensor|termux-share|termux-sms-list|termux-sms-send|termux-speech-to-text|\
    termux-storage-get|termux-telephony-call|termux-telephony-cellinfo|\
    termux-telephony-deviceinfo|termux-toast|termux-torch|termux-tts-engines|\
    termux-tts-speak|termux-usb|termux-vibrate|termux-volume|termux-wallpaper|\
    termux-wifi-connectioninfo|termux-wifi-enable|termux-wifi-scaninfo|\
    termux-wake-lock|termux-wake-unlock|termux-setup-storage)
      return 0 ;;
    *) return 1 ;;
  esac
}

echo "[warp-termux-api-bridge] watching ${QUEUE}"
while true; do
  shopt -s nullglob
  for req in "${QUEUE}"/*.req; do
    id="$(basename "$req" .req)"
    [ -f "${QUEUE}/${id}.done" ] && continue
    mapfile -t lines < "$req"
    cmd="${lines[0]:-}"
    args=()
    if [ "${#lines[@]}" -gt 1 ]; then
      args=("${lines[@]:1}")
    fi
    if ! allowed "$cmd"; then
      echo "blocked command: ${cmd}" > "${QUEUE}/${id}.err"
      echo 126 > "${QUEUE}/${id}.rc"
      : > "${QUEUE}/${id}.out"
      : > "${QUEUE}/${id}.done"
      continue
    fi
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "missing ${cmd}; pkg install termux-api and install the Termux:API app" > "${QUEUE}/${id}.err"
      echo 127 > "${QUEUE}/${id}.rc"
      : > "${QUEUE}/${id}.out"
      : > "${QUEUE}/${id}.done"
      continue
    fi
    set +e
    if [ "${#args[@]}" -gt 0 ]; then
      "$cmd" "${args[@]}" > "${QUEUE}/${id}.out" 2> "${QUEUE}/${id}.err"
    else
      "$cmd" > "${QUEUE}/${id}.out" 2> "${QUEUE}/${id}.err"
    fi
    echo $? > "${QUEUE}/${id}.rc"
    set -e
    : > "${QUEUE}/${id}.done"
  done
  sleep 0.15
done
EOF
chmod +x "${PREFIX}/bin/warp-termux-api-bridge"

info "Creating Tailcat Termux wrapper..."
cat << 'EOF' > "${PREFIX}/bin/tailcat"
#!/usr/bin/env bash
# Official Tailcat is a glibc linux binary; run it inside Ubuntu PRoot.
exec proot-distro login ubuntu -- exec tailcat "$@"
EOF
chmod +x "${PREFIX}/bin/tailcat"

info "Creating global Warp launcher..."
cat << 'EOF' > "${PREFIX}/bin/warp-agent"
#!/usr/bin/env bash
# Launch Warp Agent CLI inside PRoot Ubuntu with the Termux:API bridge mounted.
BRIDGE="${WARP_TERMUX_API_BRIDGE:-$HOME/.warp-termux-api}"
mkdir -p "${BRIDGE}/queue"

if ! pgrep -f '[w]arp-termux-api-bridge' >/dev/null 2>&1; then
  nohup warp-termux-api-bridge >/dev/null 2>&1 &
fi

if [ "${1:-}" = "login" ]; then
  echo -e "\033[0;34m[Warp Launcher]\033[0m Starting login flow... Copy any link shown into your browser."
fi

exec proot-distro login ubuntu \
  --bind "${BRIDGE}:/bridge" \
  -- exec warp "$@"
EOF
chmod +x "${PREFIX}/bin/warp-agent"

success "Installation and setup complete!"
echo ""
echo -e "${GREEN}======================================================${NC}"
echo -e "${BOLD}          HOW TO RUN WARP AGENT CLI ON TERMUX${NC}"
echo -e "${GREEN}======================================================${NC}"
echo ""
echo -e "1. Authenticate:"
echo -e "   ${YELLOW}warp-agent login${NC}"
echo ""
echo -e "2. Launch the agent:"
echo -e "   ${YELLOW}warp-agent${NC}"
echo ""
echo -e "3. Ubuntu shell:"
echo -e "   ${YELLOW}proot-distro login ubuntu --bind \"\$HOME/.warp-termux-api:/bridge\"${NC}"
echo ""
echo -e "4. Tailcat (not started automatically). Example inbound listener:"
echo -e "   ${YELLOW}tailcat serve --key=default 8022${NC}"
echo -e "   Then share the printed tc… address out of band."
echo ""
echo -e "5. Termux:API from Warp (requires the Termux:API Android app):"
echo -e "   ${YELLOW}termux-api battery-status${NC}   ${YELLOW}termux-api toast -- \"hello\"${NC}"
echo ""
