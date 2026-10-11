#!/bin/bash
# Bouwt Cliko.app en verpakt 'm in een deelbare DMG (+ .sig).
#   ./scripts/make-dmg.sh
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build.sh --release
SRC=dist/Cliko.app

STAGE=$(mktemp -d)
chmod 755 "$STAGE"
cp -R "$SRC" "$STAGE/"
cp install.sh "$STAGE/"
ln -s /Applications "$STAGE/Applications"

DMG=Cliko.dmg
rm -f "$DMG" "$DMG.sig"
hdiutil create -volname "Cliko" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

echo "✓ $DMG klaar ($(du -h "$DMG" | cut -f1))"

# Handtekening voor in-app updates (dezelfde sleutel als Usage Meter). Zonder .sig weigert de updater de DMG.
if [ -f "$HOME/.config/claude-usage/release-signing-key.pem" ]; then
    "$SRC/Contents/MacOS/Cliko" --sign-release "$DMG"
    "$SRC/Contents/MacOS/Cliko" --verify-release "$DMG" "$DMG.sig"
    echo "  Release: upload zowel $DMG als $DMG.sig"
else
    echo "⚠ Geen signing key — $DMG is niet ondertekend en kan niet via de in-app update geïnstalleerd worden."
fi
