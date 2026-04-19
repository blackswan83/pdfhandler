#!/usr/bin/env bash
# Fast debug launch for PDF Handler.
#
# Builds the app in debug configuration, wraps the binary in a real .app
# bundle (so MenuBarExtra, dock icon, document types, and services all
# work), and launches it with stderr streaming back to the terminal.
#
# Usage:
#   ./scripts/dev.sh           # one-shot debug build + launch
#   ./scripts/dev.sh --watch   # relaunch on any .swift change (needs fswatch)
#   ./scripts/dev.sh --clean   # wipe build/ first
#
# Output:
#   build/PDF Handler (Debug).app

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
PKG_DIR="$ROOT/PDFHandler"
RES_DIR="$PKG_DIR/PDFHandler/Resources"
ICONSET_SRC="$RES_DIR/Assets.xcassets/AppIcon.appiconset"
SRC_DIR="$PKG_DIR/PDFHandler"
BUILD_DIR="$ROOT/build"
APP_NAME="PDF Handler (Debug)"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
EXE_NAME="PDFHandler"

WATCH=0
DO_CLEAN=0
for arg in "$@"; do
    case "$arg" in
        --watch) WATCH=1 ;;
        --clean) DO_CLEAN=1 ;;
        -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
        *) echo "unknown arg: $arg" >&2; exit 2 ;;
    esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "This script runs on macOS only." >&2
    exit 1
fi

if (( DO_CLEAN )); then rm -rf "$BUILD_DIR"; fi
mkdir -p "$BUILD_DIR"

build_and_launch() {
    echo "→ swift build -c debug"
    ( cd "$PKG_DIR" && swift build -c debug )

    local bin_path
    bin_path="$(cd "$PKG_DIR" && swift build -c debug --show-bin-path)/$EXE_NAME"
    if [[ ! -x "$bin_path" ]]; then
        echo "build output not found: $bin_path" >&2
        return 1
    fi

    # AppIcon.icns — regenerate only if missing (sips is slow).
    if [[ ! -f "$BUILD_DIR/AppIcon.icns" ]]; then
        echo "→ building AppIcon.icns"
        local iconset="$BUILD_DIR/AppIcon.iconset"
        rm -rf "$iconset"; mkdir -p "$iconset"
        cp "$ICONSET_SRC"/icon_*.png "$iconset/"
        iconutil -c icns "$iconset" -o "$BUILD_DIR/AppIcon.icns"
    fi

    echo "→ assembling $APP_BUNDLE"
    rm -rf "$APP_BUNDLE"
    mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
    cp "$bin_path"                 "$APP_BUNDLE/Contents/MacOS/$EXE_NAME"
    chmod +x                       "$APP_BUNDLE/Contents/MacOS/$EXE_NAME"
    cp "$RES_DIR/Info.plist"       "$APP_BUNDLE/Contents/Info.plist"
    cp "$BUILD_DIR/AppIcon.icns"   "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    printf 'APPL????' >            "$APP_BUNDLE/Contents/PkgInfo"

    # Ad-hoc sign without entitlements — debug builds don't need them and
    # Gatekeeper on the dev machine doesn't enforce for local-built apps.
    codesign --force --sign - "$APP_BUNDLE" >/dev/null 2>&1 || true

    echo "→ launching"
    # -n: new instance every time (ignore already-running)
    # -W: wait for the app to quit, so Ctrl-C here quits the app
    # -g: don't steal focus? No — we want focus. Skip.
    # We redirect the app's stderr to this terminal by launching the
    # binary directly in the background after `open` takes care of the
    # bundle. `open` itself doesn't stream output, so we spawn the binary
    # directly and rely on launchd-via-open only for bundle registration.
    # Simpler approach: `open -nW` and live without live logs; use
    # Console.app to inspect os_log. (Direct-exec breaks NSApp state.)
    open -nW "$APP_BUNDLE"
}

kill_running() {
    # Best-effort: kill any running debug instance before relaunch.
    pkill -f "$APP_BUNDLE/Contents/MacOS/$EXE_NAME" 2>/dev/null || true
}

if (( WATCH )); then
    if ! command -v fswatch >/dev/null 2>&1; then
        cat >&2 <<EOF
--watch requires fswatch:
  brew install fswatch
Running one-shot build instead.
EOF
        build_and_launch
        exit 0
    fi

    echo "→ watching $SRC_DIR for .swift changes (Ctrl-C to stop)"
    build_and_launch &
    LAUNCH_PID=$!

    # Debounce: fswatch --batch-marker + read loop would be cleaner; this
    # is a simple one-event-per-burst approach with a 300ms settle.
    fswatch -0 -l 0.3 -e ".*" -i "\\.swift$" "$SRC_DIR" | while IFS= read -r -d "" _; do
        echo ""
        echo "→ change detected, rebuilding"
        kill_running
        wait "$LAUNCH_PID" 2>/dev/null || true
        build_and_launch &
        LAUNCH_PID=$!
    done
else
    build_and_launch
fi
