# Cliko — development

For users: see the [README](../README.md).

## Building from source

Requirements: macOS 12 or later and **Xcode** (the tests need XCTest).

```bash
./scripts/build.sh            # Swift tests + universal build + ad-hoc codesign
                              # → dist/Cliko Dev.app (bundle id com.jos.cliko.dev)
./scripts/build.sh --release  # same, as the real bundle → dist/Cliko.app
./scripts/deploy.sh           # release build, install to /Applications, restart LaunchAgent, verify
./scripts/make-dmg.sh         # release build + Cliko.dmg (+ .sig if the signing key is present)
(cd swift && swift test)      # tests only
```

The **dev build** runs next to the installed app: its own bundle id, a `β` next to the menu bar icon and before notification titles, and its own files (`~/Library/Application Support/Cliko Dev/`, `~/Library/Logs/Cliko-Dev.log`). Script output is in Dutch.

CI (GitHub Actions, macOS) runs the tests and a universal build on every push.

**Layout:**

- `swift/Sources/ClikoCore`: pure logic (Foundation only), tested with XCTest. Ximmio requests and parsing, the schedule (which bin is next, reminders), settings, update checks.
- `swift/Sources/Cliko`: the AppKit glue: status item, menu, address dialog, notifications, updater, uninstall.
- `swift/Resources/strings.json`: all user-facing text, Dutch and English. Every key goes in both languages (a test checks it).

## Data source

RAD's calendar comes from Ximmio (`wasteprod2api.ximmio.com`, company code `13a2cad9-36d0-4b01-b877-efcb421a864d`, as in [hacs_waste_collection_schedule](https://github.com/mampfes/hacs_waste_collection_schedule)). Two form-encoded POSTs:

1. `api/FetchAdress`: `postCode`, `houseNumber`, `companyCode` → `dataList[0].UniqueId`, `Community`
2. `api/GetCalendar`: `uniqueAddressID`, `startDate`, `endDate`, `companyCode`, `community` → `dataList[]` with `_pickupTypeText` (GREY, GREEN, PAPER, PACKAGES, …), `description` and `pickupDates`

Confirmed against a live RAD address (October 2026): the four codes above, weekly PACKAGES on Wednesday and GREEN/PAPER/GREY on Thursday. RAD sends `description` as the literal string `"Null"`, so labels come from `strings.json`. The fixtures in `swift/Tests/ClikoCoreTests/Fixtures` follow that answer.

Check the live source:

- On a Mac: `Cliko --probe <postcode> <huisnummer>` (the binary in `dist/…/Contents/MacOS/`)
- Anywhere with curl and jq: `./scripts/probe-ximmio.sh <postcode> <huisnummer>`
- In CI: Actions → **Probe Ximmio** (inputs are public: use a public address, the default is the municipal office)

## Behaviour

- On a collection day the icon moves on at noon (`pickupDayCutoffHour`), so Wednesday evening shows Thursday's bin.
- The calendar is fetched at start, every 12 hours, and 30 minutes after a failure; a fetched calendar is kept for offline use.
- Reminders are scheduled with macOS in advance (calendar triggers, up to five weeks ahead) and rescheduled after every fetch.
- Unknown waste types show as a box with Ximmio's own description.
- Icons are SF Symbols, except PMD: a tied bin bag drawn in `Cliko/Icons.swift` (SF Symbols has none). Menu rows with an icon are custom views, because plain `NSMenuItem.image` didn't show on macOS 26.
- Language: menu → Language (same as macOS, Nederlands, English); stored as `language` in `settings.json`.
- App icon: `icon/Cliko.svg`, rendered to `icon/Cliko-1024.png`; `build.sh` turns the PNG into `Cliko.icns`.

## Making a release

1. Bump `VERSION` in `scripts/build.sh` and add a `## X.Y` section at the top of `CHANGELOG.md` (it becomes the release notes). Commit and push.
2. Tag and push (`git tag vX.Y && git push origin vX.Y`), or run Actions → **Release** with the version. The workflow builds `Cliko.dmg` on macOS and publishes the release with it.
3. Sign that DMG on the release Mac and attach the signature:
   ```bash
   gh release download vX.Y -p Cliko.dmg
   dist/Cliko.app/Contents/MacOS/Cliko --sign-release Cliko.dmg   # → Cliko.dmg.sig
   gh release upload vX.Y Cliko.dmg.sig
   ```
   Without the `.sig`, installed apps refuse the update. A first install (by hand) doesn't need it.

Or build and sign locally in one go: `./scripts/make-dmg.sh`, then upload both files to a release.

Releases are signed with the same Ed25519 key as Usage Meter (`~/.config/claude-usage/release-signing-key.pem`, never in git or CI; `updatePublicKeyHex` in `ClikoCore/Update.swift`). `--sign-release` refuses a key that doesn't match.

## Pitfalls

- **Same identity across versions:** bundle id `com.jos.cliko`, executable `Cliko`, LaunchAgent `com.jos.cliko` and the files in `~/Library/Application Support/Cliko/` must stay the same, or updates break existing installs.
- **Universal builds:** releases ship arm64 + x86_64; an update is one-way.
- Log: `~/Library/Logs/Cliko.log`.
