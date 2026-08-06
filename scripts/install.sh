#!/usr/bin/env bash
#
# install.sh — install PDF Handler and stop Gatekeeper blocking it.
#
#   ./scripts/install.sh                     # newest build/*.dmg, else build/PDFHandler.app
#   ./scripts/install.sh ~/Downloads/PDFHandler-2.0.dmg
#   ./scripts/install.sh /path/to/PDFHandler.app
#
# Why this is needed: the app is ad-hoc signed (no Apple Developer ID)
# and not notarized. Anything downloaded through a browser carries a
# com.apple.quarantine flag, and quarantine + unidentified developer is
# what produces the "damaged" / "malware" dialog. The app is fine; macOS
# simply has no signature to check it against.
#
# Locally-built apps are never quarantined, so if you build on this
# machine the flag is already absent and this script just installs.

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "error: macOS only." >&2
    exit 1
fi

APP_NAME="PDFHandler.app"
DEST="/Applications/$APP_NAME"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SOURCE="${1:-}"
if [[ -z "$SOURCE" ]]; then
    # Newest DMG in build/, else the built .app.
    SOURCE="$(ls -t "$REPO_ROOT"/build/PDFHandler-*.dmg 2>/dev/null | head -n1 || true)"
    if [[ -z "$SOURCE" && -d "$REPO_ROOT/build/$APP_NAME" ]]; then
        SOURCE="$REPO_ROOT/build/$APP_NAME"
    fi
fi

if [[ -z "$SOURCE" || ! -e "$SOURCE" ]]; then
    cat >&2 <<EOF
error: nothing to install.

Pass a .dmg or .app explicitly:

    ./scripts/install.sh ~/Downloads/PDFHandler-2.0.dmg

or build one first:

    ./scripts/build-dmg.sh
EOF
    exit 1
fi

MOUNT_POINT=""
cleanup() {
    if [[ -n "$MOUNT_POINT" && -d "$MOUNT_POINT" ]]; then
        hdiutil detach "$MOUNT_POINT" -quiet || true
    fi
}
trap cleanup EXIT

case "$SOURCE" in
    *.dmg)
        echo "==> Mounting $(basename "$SOURCE")"
        MOUNT_POINT="$(mktemp -d /tmp/pdfhandler-mount.XXXXXX)"
        hdiutil attach "$SOURCE" -nobrowse -quiet -mountpoint "$MOUNT_POINT"
        APP_SOURCE="$MOUNT_POINT/$APP_NAME"
        ;;
    *.app)
        APP_SOURCE="$SOURCE"
        ;;
    *)
        echo "error: expected a .dmg or .app, got: $SOURCE" >&2
        exit 1
        ;;
esac

if [[ ! -d "$APP_SOURCE" ]]; then
    echo "error: $APP_NAME not found inside $SOURCE" >&2
    exit 1
fi

# Quit a running copy so the replacement is not held open.
if pgrep -x PDFHandler >/dev/null 2>&1; then
    echo "==> Quitting the running copy"
    osascript -e 'tell application "PDFHandler" to quit' 2>/dev/null || killall PDFHandler || true
    sleep 2
fi

echo "==> Installing to $DEST"
rm -rf "$DEST"
cp -R "$APP_SOURCE" "$DEST"

# The whole point of the script. -r because the flag lands on nested
# files too, and clearing only the bundle root leaves it blocked.
# A missing attribute is success, not failure.
echo "==> Clearing the quarantine flag"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

remaining="$(xattr -lr "$DEST" 2>/dev/null | grep -c 'com.apple.quarantine' || true)"
if [[ "${remaining:-0}" -gt 0 ]]; then
    echo "   warning: $remaining quarantine attributes still present" >&2
else
    echo "   clean"
fi

echo "==> Launching"
open "$DEST"

cat <<EOF

Installed: $DEST

If macOS still refuses to open it, the app needs a one-time approval:
  System Settings → Privacy & Security → scroll down → "Open Anyway"

To grant this specific app a permanent Gatekeeper exception instead
(leaves Gatekeeper enabled for everything else):
  sudo spctl --add --label "PDF Handler" "$DEST"
EOF
