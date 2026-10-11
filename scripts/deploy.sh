#!/bin/bash
# Herbouwt Cliko, rolt uit naar /Applications, herstart de LaunchAgent
# en verifieert dat de nieuwe build draait én de kalender ophaalt.
#   ./scripts/deploy.sh
set -euo pipefail
cd "$(dirname "$0")/.."

APP=/Applications/Cliko.app
BIN="$APP/Contents/MacOS/Cliko"
PLIST="$HOME/Library/LaunchAgents/com.jos.cliko.plist"
CALENDAR="$HOME/Library/Application Support/Cliko/calendar.json"
LOG="$HOME/Library/Logs/Cliko.log"
WAIT_SEC=30

fail() {
    echo "✗ $*" >&2
    echo "--- laatste regels $LOG" >&2
    tail -15 "$LOG" 2>/dev/null >&2 || true
    exit 1
}

./scripts/build.sh --release
[ -f "$PLIST" ] || { echo "✗ LaunchAgent ontbreekt — draai eerst ./install.sh" >&2; exit 1; }

fetched_at() { plutil -extract fetchedAt raw -o - "$CALENDAR" 2>/dev/null || true; }
BEFORE=$(fetched_at)

echo "🔄 Deploying..."
launchctl unload "$PLIST" 2>/dev/null || true
pkill -f "$BIN" 2>/dev/null || true
sleep 1
rm -rf "$APP"
cp -R dist/Cliko.app /Applications/
launchctl load "$PLIST"

for _ in $(seq 1 10); do pgrep -f "$BIN" >/dev/null && break; sleep 1; done
pgrep -f "$BIN" >/dev/null || fail "app-proces draait niet na start"
echo "✓ Build $(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP/Contents/Info.plist") draait"

# The calendar is only refetched when it's older than 12 h: a recent one counts as fine.
if [ -n "$BEFORE" ]; then
    echo "✓ kalender aanwezig (opgehaald $BEFORE)"
    exit 0
fi
printf "⏳ Wachten op eerste ophaalactie (max %ss)" "$WAIT_SEC"
for _ in $(seq 1 "$WAIT_SEC"); do
    if [ -n "$(fetched_at)" ]; then echo; echo "✓ kalender opgehaald ($(fetched_at))"; exit 0; fi
    pgrep -f "$BIN" >/dev/null || { echo; fail "app is gecrasht"; }
    printf "."
    sleep 1
done
echo
fail "geen kalender binnen ${WAIT_SEC}s (adres ingesteld?)"
