#!/bin/bash
# Installeert Cliko als achtergrond-app (LaunchAgent) voor de huidige gebruiker.
# Vereist: Cliko.app staat al in /Applications.
set -e

APP=/Applications/Cliko.app
LABEL=com.jos.cliko
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

if [ ! -d "$APP" ]; then
    echo "✗ $APP niet gevonden. Sleep Cliko eerst naar Applications."
    exit 1
fi

# De app is niet Apple-notarized. Zonder deze stap blokkeert Gatekeeper de eerste start.
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$APP/Contents/MacOS/Cliko</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
    <key>StandardOutPath</key>
    <string>/tmp/cliko.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/cliko-error.log</string>
</dict>
</plist>
PLIST

launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"

echo "✓ Cliko geïnstalleerd en gestart."
echo "  Vul je postcode en huisnummer in; sta meldingen toe voor de herinnering de avond ervoor."
echo "  Logboek: ~/Library/Logs/Cliko.log"
