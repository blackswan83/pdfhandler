#!/usr/bin/env bash
# Build PDF Handler.app and PDFHandler.dmg from a SwiftPM release build.
#
# Requires macOS with:
#   - Xcode command line tools (swift, iconutil, codesign, hdiutil, plutil)
#
# Usage:
#   ./scripts/package.sh              # build .app and .dmg
#   ./scripts/package.sh --app-only   # just .app
#   ./scripts/package.sh --clean      # nuke build/ first
#
# Output:
#   build/PDF Handler.app
#   build/PDFHandler.dmg

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
PKG_DIR="$ROOT/PDFHandler"                              # where Package.swift lives
RES_DIR="$PKG_DIR/PDFHandler/Resources"
ICONSET_SRC="$RES_DIR/Assets.xcassets/AppIcon.appiconset"
BUILD_DIR="$ROOT/build"
APP_NAME="PDF Handler"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
EXE_NAME="PDFHandler"
DMG_PATH="$BUILD_DIR/PDFHandler.dmg"

APP_ONLY=0
DO_CLEAN=0
for arg in "$@"; do
    case "$arg" in
        --app-only) APP_ONLY=1 ;;
        --clean)    DO_CLEAN=1 ;;
        -h|--help)  sed -n '2,20p' "$0"; exit 0 ;;
        *) echo "unknown arg: $arg" >&2; exit 2 ;;
    esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "This script runs on macOS only." >&2
    exit 1
fi

if (( DO_CLEAN )); then
    rm -rf "$BUILD_DIR"
fi
mkdir -p "$BUILD_DIR"

# ------------------------------------------------------------------
# 1. Build the executable via SwiftPM (pbxproj is stale; this is the
#    reliable path).
# ------------------------------------------------------------------
echo "→ swift build -c release"
( cd "$PKG_DIR" && swift build -c release )

BIN_PATH="$(cd "$PKG_DIR" && swift build -c release --show-bin-path)/$EXE_NAME"
if [[ ! -x "$BIN_PATH" ]]; then
    echo "build output not found: $BIN_PATH" >&2
    exit 1
fi

# ------------------------------------------------------------------
# 2. Assemble AppIcon.icns from the appiconset PNGs.
# ------------------------------------------------------------------
echo "→ building AppIcon.icns"
ICONSET_TMP="$BUILD_DIR/AppIcon.iconset"
rm -rf "$ICONSET_TMP"
mkdir -p "$ICONSET_TMP"
for f in "$ICONSET_SRC"/icon_*.png; do
    cp "$f" "$ICONSET_TMP/"
done
iconutil -c icns "$ICONSET_TMP" -o "$BUILD_DIR/AppIcon.icns"

# ------------------------------------------------------------------
# 3. Assemble the .app bundle.
# ------------------------------------------------------------------
echo "→ assembling $APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BIN_PATH"                       "$APP_BUNDLE/Contents/MacOS/$EXE_NAME"
chmod +x                             "$APP_BUNDLE/Contents/MacOS/$EXE_NAME"
cp "$RES_DIR/Info.plist"             "$APP_BUNDLE/Contents/Info.plist"
cp "$BUILD_DIR/AppIcon.icns"         "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

# PkgInfo — harmless, macOS still reads it.
printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

# ------------------------------------------------------------------
# 4. Ad-hoc sign so Gatekeeper doesn't flat-out refuse.
#    Replace with a Developer ID signature + notarization for public
#    distribution.
# ------------------------------------------------------------------
echo "→ ad-hoc codesigning"
codesign --force --deep --sign - \
         --options runtime \
         --entitlements "$RES_DIR/PDFHandler.entitlements" \
         "$APP_BUNDLE" 2>&1 | tail -5 || {
    # Entitlements may fail with ad-hoc; retry without.
    echo "  retrying without entitlements"
    codesign --force --deep --sign - "$APP_BUNDLE"
}

# Quick sanity check.
codesign --verify --deep --strict "$APP_BUNDLE" && echo "  signature ok"

echo ""
echo "✓ $APP_BUNDLE"

if (( APP_ONLY )); then
    exit 0
fi

# ------------------------------------------------------------------
# 5. Build a compressed DMG using hdiutil — no Homebrew dependency.
# ------------------------------------------------------------------
echo "→ building DMG"
STAGING="$BUILD_DIR/dmg-staging"
rm -rf "$STAGING" "$DMG_PATH"
mkdir -p "$STAGING"
cp -R "$APP_BUNDLE" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null

rm -rf "$STAGING"

echo ""
echo "✓ $DMG_PATH"
echo ""
echo "First-run note: because this is ad-hoc signed, users will see a"
echo "Gatekeeper warning. They can right-click the app → Open to bypass."
echo "For friction-free distribution, sign with a Developer ID and notarize:"
echo "  codesign --sign \"Developer ID Application: …\" …"
echo "  xcrun notarytool submit $DMG_PATH --team-id … --apple-id … --wait"
