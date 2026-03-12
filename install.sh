#!/bin/bash
set -e

# ─────────────────────────────────────────────────────────────────────────────
#  AuraBook — One-line macOS Installer
#
#  Usage:
#    curl -fsSL https://raw.githubusercontent.com/aakashdahake/aurabook-releases/main/install.sh | bash
#
#  What it does:
#    1. Downloads the latest AuraBook DMG from GitHub Releases
#    2. Mounts the DMG
#    3. Copies AuraBook.app → /Applications
#    4. Runs `xattr -cr` to clear the Gatekeeper quarantine flag
#    5. Unmounts the DMG and removes the temp file
# ─────────────────────────────────────────────────────────────────────────────

REPO="aakashdahake/aurabook-releases"
APP_NAME="AuraBook"
INSTALL_DIR="/Applications"

# ── Colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'
info()    { echo -e "${BLUE}${BOLD}ℹ︎  $*${RESET}"; }
success() { echo -e "${GREEN}${BOLD}✅  $*${RESET}"; }
warn()    { echo -e "${YELLOW}${BOLD}⚠️  $*${RESET}"; }
error()   { echo -e "${RED}${BOLD}❌  $*${RESET}"; exit 1; }

# ── Platform check ────────────────────────────────────────────────────────────
[[ "$(uname)" == "Darwin" ]] || error "This installer only supports macOS."

echo ""
echo -e "${BOLD}╔══════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║   AuraBook — macOS Installer         ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════╝${RESET}"
echo ""

# ── Resolve latest release version ───────────────────────────────────────────
info "Fetching latest release info..."

LATEST_JSON=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest")
VERSION=$(echo "$LATEST_JSON" | grep '"tag_name"' | head -1 | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')
DMG_URL=$(echo "$LATEST_JSON" | grep '"browser_download_url"' | grep '\.dmg"' | head -1 | sed -E 's/.*"browser_download_url": *"([^"]+)".*/\1/')

[[ -n "$VERSION" ]]  || error "Could not determine latest version."
[[ -n "$DMG_URL" ]]  || error "Could not find a DMG asset in the latest release."

info "Latest version : ${VERSION}"
info "Download URL   : ${DMG_URL}"
echo ""

# ── Download ──────────────────────────────────────────────────────────────────
TMP_DMG=$(mktemp /tmp/AuraBook-XXXXXX.dmg)
trap 'rm -f "$TMP_DMG"' EXIT

info "Downloading ${APP_NAME} ${VERSION}..."
curl -L --progress-bar -o "$TMP_DMG" "$DMG_URL"
echo ""

# ── Mount DMG ─────────────────────────────────────────────────────────────────
info "Mounting DMG..."
MOUNT_POINT=$(mktemp -d /tmp/AuraBook-mount-XXXXXX)
hdiutil attach "$TMP_DMG" -nobrowse -noautoopen -readonly -mountpoint "$MOUNT_POINT" -quiet \
  || error "Failed to mount the DMG."
info "Mounted at: ${MOUNT_POINT}"

# Ensure we unmount even if something goes wrong
trap 'hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true; rm -rf "$MOUNT_POINT"; rm -f "$TMP_DMG"' EXIT

# ── Copy to /Applications ─────────────────────────────────────────────────────
SRC_APP=$(find "$MOUNT_POINT" -maxdepth 1 -name "*.app" | head -1)
[[ -n "$SRC_APP" ]] || error "Could not find .app bundle inside the DMG."

DEST_APP="${INSTALL_DIR}/${APP_NAME}.app"

if [[ -d "$DEST_APP" ]]; then
  warn "${APP_NAME}.app already exists in /Applications — replacing..."
  rm -rf "$DEST_APP"
fi

info "Installing ${APP_NAME}.app → ${INSTALL_DIR}..."
cp -R "$SRC_APP" "$DEST_APP"

# ── Strip Gatekeeper quarantine ───────────────────────────────────────────────
info "Clearing Gatekeeper quarantine flag (xattr -cr)..."
xattr -cr "$DEST_APP"

# ── Unmount ───────────────────────────────────────────────────────────────────
info "Unmounting DMG..."
hdiutil detach "$MOUNT_POINT" -quiet

# Reset trap (no longer need to unmount)
trap 'rm -rf "$MOUNT_POINT"; rm -f "$TMP_DMG"' EXIT

echo ""
success "${APP_NAME} ${VERSION} installed successfully!"
echo ""
echo -e "  ${BOLD}Open it:${RESET}  open \"${DEST_APP}\""
echo -e "  ${BOLD}Or find it in Launchpad / Applications folder.${RESET}"
echo ""

