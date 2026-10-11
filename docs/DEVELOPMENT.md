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

## Making a release

1. Bump `VERSION` in `scripts/build.sh`. Commit and push.
2. `./scripts/make-dmg.sh` creates `Cliko.dmg` and `Cliko.dmg.sig`.
3. Create a GitHub release with tag `vX.Y` and **both** files attached. Without the `.sig`, the in-app updater rejects the release.

Releases are signed with the same Ed25519 key as Usage Meter (`~/.config/claude-usage/release-signing-key.pem`, never in git; `updatePublicKeyHex` in `ClikoCore/Update.swift`). `--sign-release` refuses a key that doesn't match.

## Pitfalls

- **Same identity across versions:** bundle id `com.jos.cliko`, executable `Cliko`, LaunchAgent `com.jos.cliko` and the files in `~/Library/Application Support/Cliko/` must stay the same, or updates break existing installs.
- **Universal builds:** releases ship arm64 + x86_64; an update is one-way.
- Log: `~/Library/Logs/Cliko.log`.
