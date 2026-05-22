#!/usr/bin/env bash
#
# build-dmg.sh — Build PDF Handler as a .app and package it as a DMG.
#
# Terminal-only build: uses `swift build` (Swift Package Manager) to compile,
# then assembles the .app bundle by hand and packages it with `hdiutil`.
# No Xcode IDE required — only the Command Line Tools (`xcode-select --install`).
#
# Usage:
#   ./scripts/build-dmg.sh
#   OUTPUT_DIR=/tmp/pdfhandler ./scripts/build-dmg.sh
#
# Output: build/PDFHandler-<version>.dmg   (plus build/PDFHandler.app)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PACKAGE_DIR="$REPO_ROOT/PDFHandler"
SRC_RESOURCES="$PACKAGE_DIR/PDFHandler/Resources"
APP_NAME="PDFHandler"
DISPLAY_NAME="PDF Handler"

OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/build}"
APP_BUNDLE="$OUTPUT_DIR/$APP_NAME.app"
DMG_STAGING="$OUTPUT_DIR/dmg-staging"

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
    "$SRC_RESOURCES/Info.plist" 2>/dev/null || echo "1.0")"
DMG_PATH="$OUTPUT_DIR/${APP_NAME}-${VERSION}.dmg"

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "error: this script must run on macOS (uses AppKit SDK + hdiutil)." >&2
    exit 1
fi

for cmd in swift hdiutil codesign plutil; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "error: missing required tool: $cmd" >&2
        echo "       install the Command Line Tools: xcode-select --install" >&2
        exit 1
    fi
done

echo "==> Cleaning previous build output"
rm -rf "$APP_BUNDLE" "$DMG_STAGING" "$DMG_PATH"
mkdir -p "$OUTPUT_DIR"

echo "==> Compiling with swift build (release)"
(
    cd "$PACKAGE_DIR"
    swift build -c release --product "$APP_NAME"
)

BIN_PATH="$(cd "$PACKAGE_DIR" && swift build -c release --show-bin-path)"
EXECUTABLE="$BIN_PATH/$APP_NAME"
if [[ ! -x "$EXECUTABLE" ]]; then
    echo "error: swift build did not produce $EXECUTABLE" >&2
    exit 1
fi

echo "==> Assembling $APP_NAME.app bundle"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$EXECUTABLE" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Copy the SwiftPM resource bundle next to the executable so Bundle.module resolves.
for bundle in "$BIN_PATH"/*.bundle; do
    if [[ -e "$bundle" ]]; then
        cp -R "$bundle" "$APP_BUNDLE/Contents/Resources/"
    fi
done

# Info.plist lives at Contents/Info.plist (not inside the resource bundle).
cp "$SRC_RESOURCES/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# PkgInfo is the classic 8-byte type/creator stamp for an application bundle.
printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

# Render the app icon set deterministically from scripts/render-icon.swift.
# Failure here is non-fatal — build continues without a custom icon.
if [[ -x "$SCRIPT_DIR/render-icon.swift" ]]; then
    echo "==> Rendering app icon"
    if ! swift "$SCRIPT_DIR/render-icon.swift"; then
        echo "   (icon renderer failed; continuing without custom icon)" >&2
    fi
fi

# Compile the asset catalog (icons etc.) if actool is available and assets exist.
ASSETS_SRC="$SRC_RESOURCES/Assets.xcassets"
if command -v actool >/dev/null 2>&1 && [[ -d "$ASSETS_SRC" ]]; then
    # Only compile if there is at least one real image in the icon set.
    if compgen -G "$ASSETS_SRC/AppIcon.appiconset/*.png" > /dev/null; then
        echo "==> Compiling asset catalog"
        actool \
            --compile "$APP_BUNDLE/Contents/Resources" \
            --platform macosx \
            --minimum-deployment-target 13.0 \
            --app-icon AppIcon \
            --output-partial-info-plist "$OUTPUT_DIR/assetcatalog_plist.plist" \
            --output-format human-readable-text \
            "$ASSETS_SRC" >/dev/null
        # Merge any keys actool emitted (CFBundleIconFile, CFBundleIconName) into Info.plist.
        if [[ -f "$OUTPUT_DIR/assetcatalog_plist.plist" ]]; then
            /usr/libexec/PlistBuddy -c "Merge $OUTPUT_DIR/assetcatalog_plist.plist" \
                "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true
        fi
    else
        echo "==> Skipping asset catalog (no icon PNGs present)"
    fi
fi

echo "==> Ad-hoc codesigning"
codesign --force --deep --sign - \
    --entitlements "$SRC_RESOURCES/PDFHandler.entitlements" \
    "$APP_BUNDLE"

echo "==> Validating bundle"
plutil -lint "$APP_BUNDLE/Contents/Info.plist" >/dev/null
codesign --verify --deep --strict "$APP_BUNDLE"

echo "==> Staging DMG layout"
mkdir -p "$DMG_STAGING"
cp -R "$APP_BUNDLE" "$DMG_STAGING/$APP_NAME.app"
ln -s /Applications "$DMG_STAGING/Applications"

echo "==> Creating DMG: $DMG_PATH"
hdiutil create \
    -volname "$DISPLAY_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    -fs HFS+ \
    "$DMG_PATH" >/dev/null

rm -rf "$DMG_STAGING"

echo
echo "Built: $APP_BUNDLE"
echo "DMG:   $DMG_PATH"
ls -lh "$DMG_PATH"
