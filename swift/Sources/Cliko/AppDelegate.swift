import AppKit
import ClikoCore
import UserNotifications

/// The menu bar item: one monochrome icon for the next collection, a plain
/// menu with the next four, the address and the reminder switch.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    /// `swift run` has no bundle id and counts as dev too.
    let isDev = Bundle.main.bundleIdentifier?.hasSuffix(".dev") ?? true
    var isBundled: Bool { Bundle.main.bundleURL.pathExtension == "app" }
    lazy var paths = Paths(dev: isDev)

    var strings = Strings.empty
    var lang = "en"
    var settings = Settings()
    var cache: CalendarCache?
    var fetching = false
    var lastFailure: Date?
    var lastError: String?

    var statusItem: NSStatusItem!
    var timer: Timer?
    var cutoffTimer: Timer?
    let notifyDelegate = NotificationDelegate()

    var update: Release?
    var updateChecking = false
    var updateInstalling = false

    var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }
    var calendar: Calendar { .current }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let url = Bundle.main.url(forResource: "strings", withExtension: "json") ?? Self.sourceTreeStrings,
           let loaded = try? Strings(contentsOf: url) {
            strings = loaded
        } else {
            log("strings.json niet gevonden")
        }
        settings = loadJSON(Settings.self, from: paths.settings) ?? Settings()
        lang = resolvedLanguage(settings.language, preferred: Locale.preferredLanguages)
        cache = loadJSON(CalendarCache.self, from: paths.calendar)
        log("Cliko \(version) gestart")

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu

        setupNotifications()
        refreshIcon()

        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in self?.tick() }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(tickSoon),
                                                          name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(tickSoon),
                                               name: .NSCalendarDayChanged, object: nil)
        tick()
        if !settings.hasAddress {
            DispatchQueue.main.async { self.editAddress() }
        }
    }

    /// `swift run`: no bundle, read strings.json from the source tree.
    static var sourceTreeStrings: URL? {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/strings.json")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    @objc func tickSoon(_ notification: Notification) {
        DispatchQueue.main.async { self.tick() }
    }

    /// Every 5 minutes, on wake, at midnight and at noon: redraw, fetch when due, check for updates.
    func tick() {
        refreshIcon()
        scheduleCutoff()
        if fetchDue(cache: cache, settings: settings, lastFailure: lastFailure, now: Date()) { fetch() }
        maybeCheckUpdates()
    }

    /// At noon the icon moves on to the next collection, like the menu does:
    /// a timer for that moment, so it doesn't wait for the next 5-minute tick.
    func scheduleCutoff() {
        cutoffTimer?.invalidate()
        guard let fire = nextCutoff(after: Date(), calendar: calendar) else { return }
        let noon = Timer(fire: fire, interval: 0, repeats: false) { [weak self] _ in self?.tick() }
        RunLoop.main.add(noon, forMode: .common)
        cutoffTimer = noon
    }

    func t(_ key: String, _ kw: [String: Any] = [:]) -> String { strings.t(key, lang, kw) }

    func log(_ message: String) {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let line = Data("\(f.string(from: Date())) \(message)\n".utf8)
        let url = paths.log
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line)
            try? handle.close()
        } else {
            try? line.write(to: url)
        }
    }

    // MARK: - Fetching

    func fetch() {
        guard !fetching, let postcode = settings.postcode, let number = settings.houseNumber else { return }
        fetching = true
        refreshIcon()   // "fetching collection days…" while there is nothing yet
        let cal = calendar
        Task.detached {
            let result: Result<CalendarCache, Error>
            do {
                let client = XimmioClient()
                let address = try await client.address(postcode: postcode, houseNumber: number)
                let today = Day(Date(), calendar: cal)
                let pickups = try await client.pickups(address: address,
                                                       from: today.adding(days: -1, calendar: cal) ?? today,
                                                       to: today.adding(days: 365, calendar: cal) ?? today)
                result = .success(CalendarCache(postcode: postcode, houseNumber: number,
                                                fetchedAt: Date(), pickups: pickups))
            } catch {
                result = .failure(error)
            }
            await MainActor.run { self.onFetched(result) }
        }
    }

    func onFetched(_ result: Result<CalendarCache, Error>) {
        fetching = false
        switch result {
        case .success(let fresh):
            guard fresh.matches(settings) else {   // address changed while fetching
                tick()
                return
            }
            cache = fresh
            lastFailure = nil
            lastError = nil
            do { try saveJSON(fresh, to: paths.calendar) } catch { log("kalender opslaan mislukt: \(error)") }
            log("kalender opgehaald: \(fresh.pickups.count) ophaalmomenten")
            scheduleReminders()
        case .failure(let error):
            lastFailure = Date()
            lastError = t((error as? XimmioError)?.stringKey ?? "err_network")
            log("ophalen mislukt: \(error)")
        }
        refreshIcon()
    }

    // MARK: - Menu bar

    func refreshIcon() {
        guard let button = statusItem?.button else { return }
        let now = Date()
        let next = nextPickups(upcomingPickups(cache?.pickups ?? [], now: now, calendar: calendar))
        let image: NSImage?
        let tip: String
        if !settings.hasAddress {
            image = symbolImage("trash.slash", pointSize: 14)
            tip = t("tooltip_setup")
        } else if let first = next.first {
            image = wasteIcon(first.kind, pointSize: 14)
            tip = t("tooltip_next", ["when": whenLabel(first.day, now: now, strings, lang, calendar: calendar),
                                     "what": joinedLabels(next, strings, lang)])
        } else {
            image = symbolImage("trash.slash", pointSize: 14)
            tip = lastError ?? emptyLine
        }
        button.image = image
        button.imagePosition = isDev ? .imageLeading : .imageOnly
        button.title = isDev ? "β" : ""
        button.toolTip = "Cliko — " + tip
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let now = Date()
        let upcoming = upcomingPickups(cache?.pickups ?? [], now: now, calendar: calendar)
        if !settings.hasAddress {
            menu.addItem(infoItem(t("menu_no_address")))
        } else if upcoming.isEmpty {
            menu.addItem(infoItem(lastError ?? emptyLine))
        } else {
            for p in upcoming.prefix(4) {
                let when = whenLabel(p.day, now: now, strings, lang, calendar: calendar)
                menu.addItem(iconMenuItem("\(when) — \(kindLabel(p, strings, lang))",
                                          image: wasteIcon(p.kind, pointSize: 13)))
            }
            if let lastError { menu.addItem(infoItem(lastError)) }
        }
        menu.addItem(.separator())

        let time = String(format: "%02d:%02d", settings.reminderHour, settings.reminderMinute)
        let reminders = actionItem(t("menu_reminders", ["time": time]), #selector(toggleReminders))
        reminders.state = settings.reminders ? .on : .off
        menu.addItem(reminders)
        if let postcode = settings.postcode, let number = settings.houseNumber {
            menu.addItem(actionItem(t("menu_address_set", ["postcode": formatPostcode(postcode), "number": number]),
                                    #selector(editAddress)))
        } else {
            menu.addItem(actionItem(t("menu_address"), #selector(editAddress)))
        }
        menu.addItem(languageItem())
        if let update, !updateInstalling {
            menu.addItem(actionItem(t("menu_update", ["version": update.version]), #selector(startUpdate)))
        }
        menu.addItem(actionItem(t("menu_uninstall"), #selector(confirmUninstall)))
        menu.addItem(.separator())
        menu.addItem(actionItem(t("menu_quit"), #selector(quit), key: "q"))
    }

    /// No collections to show: still fetching (a new address) or none known.
    var emptyLine: String { t(fetching ? "menu_loading" : "menu_no_pickups") }

    func infoItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    func actionItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: - Actions

    @objc func toggleReminders() {
        settings.reminders.toggle()
        saveSettings()
        log("herinneringen \(settings.reminders ? "aan" : "uit")")
        scheduleReminders()
    }

    @objc func editAddress() {
        askAddress(postcode: settings.postcode.map(formatPostcode) ?? "", number: settings.houseNumber ?? "")
    }

    /// The address dialog, filled with `postcode` and `number`. Invalid input:
    /// say so, then ask again with what was typed.
    func askAddress(postcode typedPostcode: String, number typedNumber: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = t("address_title")
        alert.informativeText = t("address_body")
        let postcode = NSTextField(frame: NSRect(x: 0, y: 32, width: 240, height: 24))
        postcode.placeholderString = t("address_postcode") + " (1234 AB)"
        postcode.stringValue = typedPostcode
        let number = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        number.placeholderString = t("address_number")
        number.stringValue = typedNumber
        postcode.nextKeyView = number
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 56))
        box.addSubview(postcode)
        box.addSubview(number)
        alert.accessoryView = box
        alert.addButton(withTitle: t("btn_save"))
        alert.addButton(withTitle: t("btn_cancel"))
        alert.window.initialFirstResponder = postcode
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        guard let pc = normalizePostcode(postcode.stringValue), let nr = normalizeHouseNumber(number.stringValue) else {
            let invalid = NSAlert()
            invalid.messageText = t("address_invalid")
            invalid.runModal()
            askAddress(postcode: postcode.stringValue, number: number.stringValue)
            return
        }
        guard pc != settings.postcode || nr != settings.houseNumber else { return }
        settings.postcode = pc
        settings.houseNumber = nr
        saveSettings()
        log("adres gewijzigd")
        cache = nil
        try? FileManager.default.removeItem(at: paths.calendar)
        lastFailure = nil
        lastError = nil
        scheduleReminders()   // drops the old address' reminders until the fetch is in
        refreshIcon()
        fetch()
    }

    /// "Language" with Same as macOS / Nederlands / English.
    func languageItem() -> NSMenuItem {
        let item = NSMenuItem(title: t("menu_language"), action: nil, keyEquivalent: "")
        let sub = NSMenu()
        sub.autoenablesItems = false
        let system = resolvedLanguage("system", preferred: Locale.preferredLanguages)
        let choices = [("system", t("lang_system", ["language": t("lang_name_" + system)])),
                       ("nl", "Nederlands"), ("en", "English")]
        for (code, title) in choices {
            let choice = actionItem(title, #selector(chooseLanguage(_:)))
            choice.representedObject = code
            choice.state = settings.language == code ? .on : .off
            sub.addItem(choice)
        }
        item.submenu = sub
        return item
    }

    @objc func chooseLanguage(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String, code != settings.language else { return }
        settings.language = code
        saveSettings()
        lang = resolvedLanguage(code, preferred: Locale.preferredLanguages)
        log("taal: \(code) → \(lang)")
        refreshIcon()
        scheduleReminders()   // reminder texts in the new language
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }

    func saveSettings() {
        do { try saveJSON(settings, to: paths.settings) } catch { log("instellingen opslaan mislukt: \(error)") }
    }
}
