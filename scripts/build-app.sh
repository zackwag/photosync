#!/usr/bin/env bash
set -euo pipefail

IDENTITY="-"
OUTPUT_DIR="dist"

while getopts "s:o:" opt; do
    case "$opt" in
        s) IDENTITY="$OPTARG" ;;
        o) OUTPUT_DIR="$OPTARG" ;;
        *) echo "Usage: $0 [-s signing-identity] [-o output-dir]" >&2; exit 1 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_DIR="$OUTPUT_DIR/PhotoSync.app"

echo "Building for arm64..."
swift build -c release --arch arm64 --package-path "$PROJECT_DIR"
echo "Building for x86_64..."
swift build -c release --arch x86_64 --package-path "$PROJECT_DIR"

echo "Creating universal binary..."
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

lipo -create \
    "$PROJECT_DIR/.build/arm64-apple-macosx/release/PhotoSyncCLI" \
    "$PROJECT_DIR/.build/x86_64-apple-macosx/release/PhotoSyncCLI" \
    -output "$APP_DIR/Contents/MacOS/photosync"

cp "$PROJECT_DIR/packaging/Info.plist" "$APP_DIR/Contents/Info.plist"

if [ -f "$PROJECT_DIR/packaging/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/packaging/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

echo "Signing with identity: $IDENTITY"
codesign --deep --force --options runtime --timestamp \
    --entitlements "$PROJECT_DIR/packaging/photosync.entitlements" \
    --sign "$IDENTITY" \
    "$APP_DIR"

echo "Built $APP_DIR"
