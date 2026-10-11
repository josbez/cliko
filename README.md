# Cliko

macOS menu bar app: which bin goes out next.

- One monochrome icon for the next collection: PMD, organic, paper or residual waste
- Follows the real calendar, holiday shifts included
- Notification the evening before (19:00)
- Click for the next four collections
- For RAD (Goeree-Overflakkee, Hoeksche Waard) via Ximmio; Dutch and English

## Requirements

- macOS 12+, Apple Silicon or Intel
- An address served by RAD

## Install

- [Download Cliko.dmg](https://github.com/josbez/cliko/releases/latest/download/Cliko.dmg), open it
- Drag **Cliko** to **Applications**
- In Terminal: `bash /Volumes/Cliko/install.sh` (starts at login, gets past Gatekeeper: the app isn't notarized)
- Enter your postcode and house number, allow notifications

## Update

- Menu → **Update to …** when there is one
- Unsigned updates are refused

## Privacy

- Talks only to Ximmio (the waste calendar) and GitHub
- Your address stays on your Mac and goes only to Ximmio

## Uninstall

- Menu → **Uninstall…**

## More

- [Development](docs/DEVELOPMENT.md) · [MIT license](LICENSE)
- Not affiliated with RAD or Ximmio
