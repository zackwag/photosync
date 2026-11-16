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

BUILD_FLAGS=(-c release --arch arm64 --package-path "$PROJECT_DIR")

echo "Building for arm64..."
swift build "${BUILD_FLAGS[@]}"
BIN_DIR="$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)"

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/PhotoSyncCLI" "$APP_DIR/Contents/MacOS/photosync"

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
