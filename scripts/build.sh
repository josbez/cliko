#!/bin/bash
# Bouwt Cliko als .app en faalt luid als er iets mis is.
#
#   ./scripts/build.sh            → dist/Cliko Dev.app (bundle-id com.jos.cliko.dev;
#                                   draait naast de gewone app, eigen instellingen en log)
#   ./scripts/build.sh --release  → dist/Cliko.app (bundle-id com.jos.cliko)
#   VERSION=1.1 OUT_DIR=/tmp/x ./scripts/build.sh
#                                 → andere versie/map, bv. voor een update-test
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.1}"
OUT_DIR="${OUT_DIR:-dist}"
MODE=dev
[ "${1:-}" = "--release" ] && MODE=release

if [ "$MODE" = dev ]; then
    NAME="Cliko Dev"; BUNDLE_ID="com.jos.cliko.dev"
else
    NAME="Cliko"; BUNDLE_ID="com.jos.cliko"
fi
APP="$OUT_DIR/$NAME.app"
BUILD=$(date +%Y%m%d.%H%M%S)

fail() { echo "✗ $*" >&2; exit 1; }

echo "🧪 Swift-tests..."
(cd swift && swift test -q 2>&1 | tail -5) || fail "Swift-tests falen — niet gebouwd"

echo "📦 Building $NAME.app..."
# Universal (Apple Silicon + Intel): an update is one-way, Intel Macs must keep working.
ARCHS=(--arch arm64 --arch x86_64)
(cd swift && swift build -c release "${ARCHS[@]}" -q) || fail "swift build faalde"
BIN="$(cd swift && swift build -c release "${ARCHS[@]}" --show-bin-path)/Cliko"
[ -x "$BIN" ] || fail "$BIN ontbreekt na build"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Cliko"
cp swift/Resources/strings.json "$APP/Contents/Resources/"
ICON_KEY=""
if [ -f icon/Cliko.icns ]; then
    cp icon/Cliko.icns "$APP/Contents/Resources/"
    ICON_KEY="<key>CFBundleIconFile</key><string>Cliko</string>"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$NAME</string>
    <key>CFBundleDisplayName</key><string>$NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>Cliko</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    $ICON_KEY
    <key>LSMinimumSystemVersion</key><string>12.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" || fail "codesign faalde"
codesign --verify "$APP" || fail "code-signature ongeldig"
echo "✓ $APP ($(du -sh "$APP" | cut -f1), build $BUILD)"
