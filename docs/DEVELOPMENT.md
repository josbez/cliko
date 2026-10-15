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

- On a collection day the icon moves on at noon (`pickupDayCutoffHour`), so Wednesday evening shows Thursday's bin. A timer fires at that moment (`nextCutoff`), so icon, tooltip and menu change together.
- The calendar is fetched at start, every 12 hours, and 30 minutes after a failure; a fetched calendar is kept for offline use. With nothing to show yet (a new address), the menu says "Fetching collection days…" until it is in.
- Reminders are scheduled with macOS in advance (calendar triggers, up to five weeks ahead) and rescheduled after every fetch.
- Unknown waste types show as a box with Ximmio's own description; without one, the code as Ximmio sends it ("KCA").
- Invalid address input: the app says so, then opens the address dialog again with what was typed.
- Icons are SF Symbols, except PMD: a tied bin bag drawn in `Cliko/Icons.swift` (SF Symbols has none). Menu rows with an icon are custom views, because plain `NSMenuItem.image` didn't show on macOS 26.
- Language: menu → Language (same as macOS, Nederlands, English); stored as `language` in `settings.json`.
- App icon: `icon/Cliko.svg`, rendered to `icon/Cliko-1024.png`; `build.sh` turns the PNG into `Cliko.icns`.

## Design system

The [Cliko design system](https://claude.ai/artifact/XaSd98r3ftzsqJtx1Xmoqy) (private Claude Design artifact) leads: the SF Symbols per waste type, point sizes, the drawn PMD bag, the app icon colours and the tone. The code and these docs follow it.

- **Look it up first.** Read its README and tokens before you change the menu, the icons or the app icon. Build with what is there.
- **Missing or wrong? Change the design system first** (a symbol, a size, a colour, a rule), then the code.
- **Every PR that changes the UI** (menu, menu bar icon, symbols, `Cliko/Icons.swift`, the app icon, user-facing copy rules) updates the design system and says what changed in its description.
- **One design system** for Cliko: revise it, never create a second one.

## Making a release

1. Bump `VERSION` in `scripts/build.sh` and add a `## X.Y` section at the top of `CHANGELOG.md` (it becomes the release notes). Commit and push.
2. On the release Mac, build and sign in one go, then publish both files (`gh release create` also makes the tag):
   ```bash
   ./scripts/make-dmg.sh   # → Cliko.dmg + Cliko.dmg.sig
   gh release create vX.Y Cliko.dmg Cliko.dmg.sig --title "Cliko X.Y" \
     --notes-file <(awk -v v="## X.Y" '$0 == v {on=1; next} /^## / {on=0} on' CHANGELOG.md)
   ```
   Without the `.sig`, installed apps refuse the update. A first install (by hand) doesn't need it.

Without the Mac at hand: Actions → **Release** (by hand, with the version) builds `Cliko.dmg` and publishes the release without a `.sig`. Sign it on the release Mac afterwards: `gh release download vX.Y -p Cliko.dmg`, `dist/Cliko.app/Contents/MacOS/Cliko --sign-release Cliko.dmg`, `gh release upload vX.Y Cliko.dmg.sig`. Until then installed apps refuse the update. Pushing a tag no longer starts the workflow.

Releases are signed with the same Ed25519 key as Usage Meter (`~/.config/claude-usage/release-signing-key.pem`, never in git or CI; `updatePublicKeyHex` in `ClikoCore/Update.swift`). `--sign-release` refuses a key that doesn't match.

## Pitfalls

- **Same identity across versions:** bundle id `com.jos.cliko`, executable `Cliko`, LaunchAgent `com.jos.cliko` and the files in `~/Library/Application Support/Cliko/` must stay the same, or updates break existing installs.
- **Universal builds:** releases ship arm64 + x86_64; an update is one-way.
- Log: `~/Library/Logs/Cliko.log`.
