#!/bin/bash
set -e

# ─────────────────────────────────────────────────────────────────────────────
#  AuraBook — One-line macOS Installer
#
#  Usage:
#    curl -fsSL https://raw.githubusercontent.com/aakashdahake/aurabook-releases/main/install.sh | bash
#
#  What it does:
#    1. Checks your macOS version and architecture
#    2. Downloads the latest AuraBook DMG from GitHub Releases
#    3. Mounts the DMG
#    4. Copies AuraBook.app → /Applications
#    5. Runs `xattr -cr` to clear the Gatekeeper quarantine flag
#    6. Unmounts the DMG and removes all temp files
#
#  Nothing is sent anywhere. No telemetry. No sudo required.
#  Source: https://github.com/aakashdahake/aurabook-releases
# ─────────────────────────────────────────────────────────────────────────────

REPO="aakashdahake/aurabook-releases"
APP_NAME="AuraBook"
INSTALL_DIR="/Applications"

# ── Colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'
info()    { echo -e "${BLUE}${BOLD}  →  ${RESET}${BOLD}$*${RESET}"; }
step()    { echo -e "${CYAN}${BOLD}  ✦  $*${RESET}"; }
success() { echo -e "${GREEN}${BOLD}  ✅  $*${RESET}"; }
warn()    { echo -e "${YELLOW}${BOLD}  ⚠️   $*${RESET}"; }
detail()  { echo -e "${DIM}       $*${RESET}"; }
error()   { echo -e "\n${RED}${BOLD}  ❌  $*${RESET}\n"; exit 1; }
divider() { echo -e "${DIM}  ────────────────────────────────────────${RESET}"; }

# ── Sudo fallback ─────────────────────────────────────────────────────────────
# Tries the command without sudo first; if it fails with a permission error,
# explains why sudo is needed and retries with sudo.
try_sudo() {
  if "$@" 2>/tmp/aurabook-err; then
    return 0
  fi
  if grep -qiE "permission denied|operation not permitted|read-only" /tmp/aurabook-err 2>/dev/null; then
    warn "Permission denied — retrying with sudo (your Mac password may be required)..."
    detail "Command: sudo $*"
    sudo "$@"
  else
    cat /tmp/aurabook-err >&2
    return 1
  fi
}

# ── Banner ────────────────────────────────────────────────────────────────────
clear 2>/dev/null || true
echo ""
echo -e "${BOLD}${CYAN}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║                                          ║"
echo "  ║        AuraBook  macOS Installer        ║"
echo "  ║                                          ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${RESET}"
echo -e "  ${DIM}Business Management — Desktop App for macOS${RESET}"
echo ""
divider
echo ""
echo -e "  ${BOLD}What this script does:${RESET}"
echo -e "  ${DIM}1.${RESET} Checks your Mac is compatible"
echo -e "  ${DIM}2.${RESET} Downloads AuraBook directly from GitHub Releases"
echo -e "  ${DIM}3.${RESET} Installs it to /Applications"
echo -e "  ${DIM}4.${RESET} Removes the macOS download quarantine flag"
echo -e "  ${DIM}5.${RESET} Cleans up all temporary files"
echo ""
echo -e "  ${DIM}No telemetry. Nothing sent anywhere.${RESET}"
echo -e "  ${DIM}Sudo is only used if /Applications requires it.${RESET}"
echo -e "  ${DIM}Source: github.com/aakashdahake/aurabook-releases${RESET}"
echo ""
divider
echo ""

# ── Platform check ────────────────────────────────────────────────────────────
step "Checking system compatibility..."

[[ "$(uname)" == "Darwin" ]] || error "This installer only supports macOS."

# macOS version
MACOS_VERSION=$(sw_vers -productVersion)
MACOS_MAJOR=$(echo "$MACOS_VERSION" | cut -d. -f1)
if [[ "$MACOS_MAJOR" -lt 12 ]]; then
  error "macOS 12 (Monterey) or later is required. You have macOS ${MACOS_VERSION}."
fi
info "macOS ${MACOS_VERSION} — compatible"

# Architecture
ARCH=$(uname -m)
case "$ARCH" in
  arm64)  info "Architecture: Apple Silicon (ARM64) — compatible" ;;
  x86_64) info "Architecture: Intel (x86_64) — compatible" ;;
  *)      error "Unsupported architecture: ${ARCH}" ;;
esac

# Disk space check (need at least 400 MB free in /Applications)
FREE_KB=$(df -k /Applications | awk 'NR==2 {print $4}')
FREE_MB=$((FREE_KB / 1024))
if [[ "$FREE_MB" -lt 400 ]]; then
  warn "Low disk space: ${FREE_MB} MB free. At least 400 MB recommended."
else
  info "Disk space: ${FREE_MB} MB free — OK"
fi

echo ""
divider
echo ""

# ── Resolve latest release version ───────────────────────────────────────────
step "Fetching latest release from GitHub..."

LATEST_JSON=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest") \
  || error "Could not reach GitHub API. Check your internet connection."

VERSION=$(echo "$LATEST_JSON" | grep '"tag_name"' | head -1 | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')
DMG_URL=$(echo "$LATEST_JSON" | grep '"browser_download_url"' | grep '\.dmg"' | head -1 | sed -E 's/.*"browser_download_url": *"([^"]+)".*/\1/')
RELEASE_DATE=$(echo "$LATEST_JSON" | grep '"published_at"' | head -1 | sed -E 's/.*"published_at": *"([^"]+)".*/\1/' | cut -dT -f1)

[[ -n "$VERSION" ]] || error "Could not determine latest version."
[[ -n "$DMG_URL"  ]] || error "Could not find a DMG asset in the latest release."

info "Version        : ${VERSION}"
info "Released       : ${RELEASE_DATE}"
info "Download source: github.com/${REPO}"
detail "${DMG_URL}"

echo ""
divider
echo ""

# ── Download ──────────────────────────────────────────────────────────────────
step "Downloading ${APP_NAME} ${VERSION}..."

TMP_DMG=$(mktemp /tmp/AuraBook-XXXXXX.dmg)
trap 'rm -f "$TMP_DMG"' EXIT

curl -L --progress-bar -o "$TMP_DMG" "$DMG_URL" \
  || error "Download failed. Check your internet connection and try again."

DMG_SIZE=$(du -sh "$TMP_DMG" | cut -f1)
echo ""
success "Download complete — ${DMG_SIZE}"

echo ""
divider
echo ""

# ── Mount DMG ─────────────────────────────────────────────────────────────────
step "Mounting installer image..."

MOUNT_POINT=$(mktemp -d /tmp/AuraBook-mount-XXXXXX)
hdiutil attach "$TMP_DMG" -nobrowse -noautoopen -readonly -mountpoint "$MOUNT_POINT" -quiet \
  || error "Failed to mount the DMG."

trap 'hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true; rm -rf "$MOUNT_POINT"; rm -f "$TMP_DMG"' EXIT

info "Mounted at: ${MOUNT_POINT}"

# ── Locate .app inside DMG ────────────────────────────────────────────────────
SRC_APP=$(find "$MOUNT_POINT" -maxdepth 1 -name "*.app" | head -1)
[[ -n "$SRC_APP" ]] || error "Could not find .app bundle inside the DMG."
info "Found bundle : $(basename "$SRC_APP")"

echo ""
divider
echo ""

# ── Install to /Applications ──────────────────────────────────────────────────
DEST_APP="${INSTALL_DIR}/${APP_NAME}.app"
step "Installing to ${INSTALL_DIR}..."

if [[ -d "$DEST_APP" ]]; then
  warn "Existing installation found — replacing with ${VERSION}..."
  try_sudo rm -rf "$DEST_APP"
fi

try_sudo cp -R "$SRC_APP" "$DEST_APP"
success "Copied to /Applications/AuraBook.app"

# ── Strip Gatekeeper quarantine ───────────────────────────────────────────────
step "Clearing macOS quarantine flag..."
info "Running: xattr -cr /Applications/AuraBook.app"
detail "macOS marks downloaded apps as 'quarantined' to show a security warning."
detail "This step removes that flag so AuraBook opens directly without any prompt."
try_sudo xattr -cr "$DEST_APP"
success "Quarantine flag cleared — app is ready to open"

echo ""
divider
echo ""

# ── Unmount & cleanup ─────────────────────────────────────────────────────────
step "Cleaning up..."
hdiutil detach "$MOUNT_POINT" -quiet
trap 'rm -rf "$MOUNT_POINT"; rm -f "$TMP_DMG"' EXIT
rm -rf "$MOUNT_POINT"
rm -f  "$TMP_DMG"
info "Temporary files removed"

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║                                          ║"
echo "  ║   🎉  AuraBook installed successfully!   ║"
echo "  ║                                          ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${RESET}"
echo -e "  ${BOLD}Version  :${RESET} ${VERSION}"
echo -e "  ${BOLD}Location :${RESET} /Applications/AuraBook.app"
echo ""
echo -e "  ${BOLD}How to open:${RESET}"
echo -e "  ${DIM}•${RESET} Double-click ${BOLD}AuraBook${RESET} in your Applications folder"
echo -e "  ${DIM}•${RESET} Or run:  ${CYAN}open /Applications/AuraBook.app${RESET}"
echo -e "  ${DIM}•${RESET} Or search ${BOLD}AuraBook${RESET} in Spotlight  (⌘ Space)"
echo ""
echo -e "  ${DIM}Your data is stored locally on your Mac.${RESET}"
echo -e "  ${DIM}Nothing is uploaded to any server.${RESET}"
echo ""
divider
echo ""

