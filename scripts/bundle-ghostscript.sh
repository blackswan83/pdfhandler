#!/usr/bin/env bash
#
# bundle-ghostscript.sh — vendor the locally-installed Ghostscript into
# PDFHandler.app so the Compress tab works with no Homebrew prerequisite.
#
#   ./scripts/bundle-ghostscript.sh build/PDFHandler.app
#
# Normally invoked for you by:
#
#   BUNDLE_GHOSTSCRIPT=1 ./scripts/build-dmg.sh
#
# ── LICENSING, READ THIS ─────────────────────────────────────────────
# Ghostscript is AGPLv3. Copyleft obligations attach to *distribution*,
# not to use: a build you make and install on your own machine carries
# no obligation at all. Publishing the resulting .app or .dmg to anyone
# else does — Artifex's position is that shipping Ghostscript with an
# application requires that application to be AGPL too, or to hold a
# commercial licence from them.
#
# This repository is MIT and its CI publishes release DMGs, which is
# why bundling is opt-in and off by default. Keep it that way unless
# you have relicensed the project or bought a commercial licence.
# ─────────────────────────────────────────────────────────────────────
#
# What it does: copies the gs executable into Contents/MacOS/, copies
# every non-system dylib it needs (transitively) into
# Contents/Frameworks/, rewrites the load commands to @executable_path,
# and copies the Resource/ and lib/ trees gs needs to initialize into
# Contents/Resources/ghostscript/.

set -euo pipefail

APP_BUNDLE="${1:-}"
if [[ -z "$APP_BUNDLE" || ! -d "$APP_BUNDLE" ]]; then
    echo "usage: $0 <path/to/PDFHandler.app>" >&2
    exit 2
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "error: macOS only (uses otool/install_name_tool)." >&2
    exit 1
fi

for cmd in otool install_name_tool codesign; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "error: missing required tool: $cmd" >&2
        exit 1
    }
done

# ── Locate the source Ghostscript ────────────────────────────────────

GS_BIN="${GS_BIN:-$(command -v gs || true)}"
if [[ -z "$GS_BIN" || ! -x "$GS_BIN" ]]; then
    cat >&2 <<'EOF'
error: no `gs` found to bundle.

Install one first (it is only needed at build time; the result is
self-contained):

    brew install ghostscript

or point this script at an existing binary:

    GS_BIN=/path/to/gs ./scripts/bundle-ghostscript.sh build/PDFHandler.app
EOF
    exit 1
fi
GS_BIN="$(cd "$(dirname "$GS_BIN")" && pwd)/$(basename "$GS_BIN")"

# gs keeps its init files under <prefix>/share/ghostscript/<version>/.
GS_VERSION="$("$GS_BIN" --version 2>/dev/null || echo "")"
[[ -n "$GS_VERSION" ]] || { echo "error: '$GS_BIN --version' failed" >&2; exit 1; }

GS_PREFIX="$(cd "$(dirname "$GS_BIN")/.." && pwd)"
GS_SHARE=""
for candidate in \
    "$GS_PREFIX/share/ghostscript/$GS_VERSION" \
    "$GS_PREFIX/share/ghostscript/current" \
    "/opt/homebrew/share/ghostscript/$GS_VERSION" \
    "/usr/local/share/ghostscript/$GS_VERSION"
do
    if [[ -d "$candidate/Resource/Init" ]]; then
        GS_SHARE="$candidate"
        break
    fi
done

if [[ -z "$GS_SHARE" ]]; then
    echo "error: could not find the Ghostscript Resource tree for $GS_BIN ($GS_VERSION)." >&2
    echo "       looked under $GS_PREFIX/share/ghostscript/" >&2
    exit 1
fi

echo "==> Bundling Ghostscript $GS_VERSION"
echo "    binary:    $GS_BIN"
echo "    resources: $GS_SHARE"

MACOS_DIR="$APP_BUNDLE/Contents/MacOS"
FRAMEWORKS_DIR="$APP_BUNDLE/Contents/Frameworks"
GS_DEST="$APP_BUNDLE/Contents/Resources/ghostscript"

mkdir -p "$MACOS_DIR" "$FRAMEWORKS_DIR" "$GS_DEST"

cp "$GS_BIN" "$MACOS_DIR/gs"
chmod +x "$MACOS_DIR/gs"

# ── Copy the dylibs gs needs, transitively ───────────────────────────
#
# System libraries (/usr/lib, /System) are guaranteed present and must
# NOT be copied. Everything else — libjpeg, libpng, libtiff, freetype,
# lcms2, openjp2, idn2 … — travels with the app.

is_system_lib() {
    case "$1" in
        /usr/lib/*|/System/*|@rpath/*|@executable_path/*|@loader_path/*) return 0 ;;
        *) return 1 ;;
    esac
}

# Breadth-first over the dependency graph. Walked with an index rather
# than by shifting the array: macOS ships bash 3.2, where slicing an
# array down to empty under `set -u` is a minefield.
declare -a QUEUE=("$MACOS_DIR/gs")
declare -a COPIED=()
QUEUE_INDEX=0

already_copied() {
    local needle="$1" item
    for item in ${COPIED+"${COPIED[@]}"}; do
        [[ "$item" == "$needle" ]] && return 0
    done
    return 1
}

while [[ $QUEUE_INDEX -lt ${#QUEUE[@]} ]]; do
    current="${QUEUE[$QUEUE_INDEX]}"
    QUEUE_INDEX=$((QUEUE_INDEX + 1))

    # Skip the leading "<file>:" line and the id line of a dylib.
    while read -r dep; do
        [[ -n "$dep" ]] || continue
        is_system_lib "$dep" && continue

        base="$(basename "$dep")"
        dest="$FRAMEWORKS_DIR/$base"

        if ! already_copied "$base"; then
            if [[ ! -f "$dep" ]]; then
                echo "    warning: dependency not found, skipping: $dep" >&2
                continue
            fi
            cp -L "$dep" "$dest"
            chmod u+w "$dest"
            install_name_tool -id "@executable_path/../Frameworks/$base" "$dest" 2>/dev/null || true
            COPIED+=("$base")
            QUEUE+=("$dest")
            echo "    + $base"
        fi

        # Repoint whoever referenced it at the bundled copy.
        install_name_tool -change "$dep" "@executable_path/../Frameworks/$base" "$current" 2>/dev/null || true
    done < <(otool -L "$current" | tail -n +2 | awk '{print $1}')
done

# ── Resource + lib trees ─────────────────────────────────────────────

echo "==> Copying Ghostscript Resource tree"
rm -rf "$GS_DEST/Resource" "$GS_DEST/lib"
cp -R "$GS_SHARE/Resource" "$GS_DEST/Resource"
# NB: a bare `[[ -d x ]] && cp ...` would abort the script under set -e
# whenever the directory is absent.
if [[ -d "$GS_SHARE/lib" ]]; then
    cp -R "$GS_SHARE/lib" "$GS_DEST/lib"
fi

# The app reads GS_LIB from these paths; fail loudly if the layout is
# wrong rather than shipping a gs that cannot start.
[[ -f "$GS_DEST/Resource/Init/gs_init.ps" ]] || {
    echo "error: bundled Resource tree is missing Init/gs_init.ps" >&2
    exit 1
}

# Ship the licence next to the binary it covers.
for doc in "$GS_SHARE/../doc/COPYING" "$GS_PREFIX/share/doc/ghostscript/COPYING" "$GS_SHARE/doc/COPYING"; do
    if [[ -f "$doc" ]]; then
        cp "$doc" "$GS_DEST/COPYING-Ghostscript-AGPL.txt"
        break
    fi
done
cat > "$GS_DEST/README-Ghostscript.txt" <<EOF
This application bundles Ghostscript $GS_VERSION, which is licensed under
the GNU Affero General Public License v3.

Source for the exact version bundled here is available from
https://ghostscript.com/releases/ and https://github.com/ArtifexSoftware/ghostpdl

Ghostscript is invoked as a separate process via its documented
command-line interface. If you redistribute this application with
Ghostscript bundled, AGPL obligations apply to you — see
scripts/bundle-ghostscript.sh.
EOF

# ── Re-sign: nested code first, then the app ─────────────────────────
#
# codesign --deep is unreliable for nested helpers; sign bottom-up.

echo "==> Signing bundled Ghostscript"
SIGN_ID="${CODESIGN_IDENTITY:--}"
for lib in "$FRAMEWORKS_DIR"/*.dylib; do
    [[ -e "$lib" ]] || continue
    codesign --force --sign "$SIGN_ID" --timestamp=none "$lib"
done
codesign --force --sign "$SIGN_ID" --timestamp=none "$MACOS_DIR/gs"

echo "==> Ghostscript bundled ($(du -sh "$GS_DEST" | cut -f1) resources, $(ls -1 "$FRAMEWORKS_DIR" 2>/dev/null | wc -l | tr -d ' ') dylibs)"
