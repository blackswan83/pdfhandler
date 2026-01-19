#!/bin/bash
# Icon Generator for macOS App
# Usage: ./generate_icons.sh /path/to/source_icon.png

SOURCE="$1"
DEST_DIR="$(dirname "$0")"

if [ -z "$SOURCE" ]; then
    echo "Usage: ./generate_icons.sh /path/to/source_icon.png"
    echo "Source image should be at least 1024x1024 pixels"
    exit 1
fi

if [ ! -f "$SOURCE" ]; then
    echo "Error: Source file not found: $SOURCE"
    exit 1
fi

echo "Generating macOS app icons from: $SOURCE"
echo "Output directory: $DEST_DIR"

# Generate all required sizes
sips -z 16 16 "$SOURCE" --out "$DEST_DIR/icon_16x16.png"
sips -z 32 32 "$SOURCE" --out "$DEST_DIR/icon_16x16@2x.png"
sips -z 32 32 "$SOURCE" --out "$DEST_DIR/icon_32x32.png"
sips -z 64 64 "$SOURCE" --out "$DEST_DIR/icon_32x32@2x.png"
sips -z 128 128 "$SOURCE" --out "$DEST_DIR/icon_128x128.png"
sips -z 256 256 "$SOURCE" --out "$DEST_DIR/icon_128x128@2x.png"
sips -z 256 256 "$SOURCE" --out "$DEST_DIR/icon_256x256.png"
sips -z 512 512 "$SOURCE" --out "$DEST_DIR/icon_256x256@2x.png"
sips -z 512 512 "$SOURCE" --out "$DEST_DIR/icon_512x512.png"
sips -z 1024 1024 "$SOURCE" --out "$DEST_DIR/icon_512x512@2x.png"

echo "Done! Generated 10 icon sizes."
echo "Rebuild your Xcode project to see the new icon."
