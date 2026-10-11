import AppKit
import ClikoCore

/// In-app updates, as in Usage Meter: check GitHub once a day, download,
/// verify (Ed25519 signature, bundle id, version, code signature), stage, then
/// swap the bundle from a detached script with rollback and restart.
///
/// The expected bundle id is our own: the dev build only ever updates to a dev
/// build, never to the released app.
extension AppDelegate {
    static let workPrefix = "cliko-update-"

    func maybeCheckUpdates() {
        guard isBundled, !updateChecking, !updateInstalling, settings.updateCheck else { return }
        let stored = loadJSON(UpdateState.self, from: paths.updateState) ?? UpdateState()
        if update == nil, let latest = stored.latest, isNewer(latest.version, than: version) {
            update = latest   // remembered from an earlier check, no network needed
        }
        guard updateCheckDue(stored, now: Date()) else { return }
        updateChecking = true
        DispatchQueue.global(qos: .utility).async {
            var release: Release?
            var failure: UpdateError?
            do {
                release = parseRelease(try Self.curl(updateAPIURL, timeout: 20))
                if release == nil { failure = UpdateError("bad_response") }
            } catch let e as UpdateError {
                failure = e
            } catch {
                failure = UpdateError("unexpected", ["detail": "\(error)"])
            }
            let result = (release, failure)
            DispatchQueue.main.async { self.onUpdateChecked(result.0, result.1) }
        }
    }

    func onUpdateChecked(_ release: Release?, _ error: UpdateError?) {
        updateChecking = false
        var stored = loadJSON(UpdateState.self, from: paths.updateState) ?? UpdateState()
        stored.lastCheck = Date()
        if let error {
            log("update-check mislukt: \(error)")
        } else if let release, isNewer(release.version, than: version) {
            stored.latest = release
            update = release
            if stored.notifiedVersion != release.version {
                stored.notifiedVersion = release.version
                log("update beschikbaar: \(release.version)")
                post(id: "update-\(release.version)", title: t("notif_update_title", ["version": release.version]),
                     body: t("notif_update_body"))
            }
        } else {
            stored.latest = release
            update = nil
        }
        do { try saveJSON(stored, to: paths.updateState) } catch { log("update-status opslaan mislukt: \(error)") }
    }

    @objc func startUpdate() {
        guard let release = update, !updateInstalling else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = t("alert_install_title", ["version": release.version])
        alert.informativeText = t("alert_install_body", ["current": version])
        alert.addButton(withTitle: t("btn_update"))
        alert.addButton(withTitle: t("btn_later"))
        let notes = URL(string: release.htmlURL)
        if notes != nil, !release.htmlURL.isEmpty { alert.addButton(withTitle: t("btn_whats_new")) }
        let choice = alert.runModal()
        if choice == .alertThirdButtonReturn, let notes {
            NSWorkspace.shared.open(notes)
            return
        }
        guard choice == .alertFirstButtonReturn else { return }

        log("update naar \(release.version) gestart")
        updateInstalling = true
        let current = version
        let expectedID = Bundle.main.bundleIdentifier ?? ""
        DispatchQueue.global(qos: .userInitiated).async {
            var staged: URL?
            var failure: UpdateError?
            do {
                staged = try Self.downloadAndStage(release, current: current, bundleID: expectedID)
            } catch let e as UpdateError {
                failure = e
            } catch {
                failure = UpdateError("unexpected", ["detail": "\(error)"])
            }
            let result = (staged, failure)
            DispatchQueue.main.async { self.onUpdateStaged(result.0, result.1) }
        }
    }

    func onUpdateStaged(_ staged: URL?, _ error: UpdateError?) {
        guard let staged, error == nil else {
            let e = error ?? UpdateError("unexpected", ["detail": "?"])
            updateInstalling = false
            log("update mislukt: \(e)")
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = t("alert_failed_title")
            alert.informativeText = e.message(strings, lang)
            alert.runModal()
            return
        }
        let target = Bundle.main.bundleURL
        log("update klaargezet, vervangen van \(target.path) en herstarten")
        do {
            try Self.launchSwap(staged: staged, target: target, pid: getpid(),
                                label: Paths.launchAgentLabel, logFile: paths.log)
        } catch {
            onUpdateStaged(nil, UpdateError("install", ["detail": "\(error)"]))
            return
        }
        NSApp.terminate(nil)
    }

    // MARK: - Work off the main thread

    @discardableResult
    static func run(_ tool: String, _ args: [String]) -> (status: Int32, out: Data, err: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        guard (try? p.run()) != nil else { return (-1, Data(), "kan \(tool) niet starten") }
        let o = out.fileHandleForReading.readDataToEndOfFile()
        let e = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, o, String(decoding: e, as: UTF8.self))
    }

    static func curl(_ url: URL, to out: URL? = nil, timeout: Int) throws -> Data {
        var args = ["-fsSL", "--max-time", String(timeout),
                    "-H", "Accept: application/vnd.github+json", "-H", "User-Agent: Cliko-updater"]
        if let out { args += ["-o", out.path] }
        let r = run("/usr/bin/curl", args + [url.absoluteString])
        guard r.status == 0 else {
            let detail = r.err.trimmingCharacters(in: .whitespacesAndNewlines)
            throw UpdateError("download", ["detail": detail.isEmpty ? "\(r.status)" : detail])
        }
        return r.out
    }

    static func detach(_ mnt: URL) {
        guard FileManager.default.fileExists(atPath: mnt.path) else { return }
        if run("/usr/bin/hdiutil", ["detach", "-quiet", mnt.path]).status != 0 {
            run("/usr/bin/hdiutil", ["detach", "-quiet", "-force", mnt.path])
        }
    }

    /// Remove work dirs (and mounts) left behind by earlier failed updates.
    static func cleanupStale() {
        let tmp = FileManager.default.temporaryDirectory
        for name in (try? FileManager.default.contentsOfDirectory(atPath: tmp.path)) ?? []
        where name.hasPrefix(workPrefix) {
            let dir = tmp.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("swap.sh").path) {
                continue   // a swap may still be running from this dir
            }
            detach(dir.appendingPathComponent("mnt"))
            try? FileManager.default.removeItem(at: dir)
        }
    }

    /// Download the release DMG, verify its signature and contents, and copy the
    /// new app to a private temp dir. Never touches the installed app.
    static func downloadAndStage(_ release: Release, current: String, bundleID: String) throws -> URL {
        guard !release.dmgURL.isEmpty, let dmgURL = URL(string: release.dmgURL) else { throw UpdateError("no_dmg") }
        guard !release.sigURL.isEmpty, let sigURL = URL(string: release.sigURL) else { throw UpdateError("unsigned") }
        guard isNewer(release.version, than: current) else {
            throw UpdateError("not_newer", ["new": release.version, "current": current])
        }

        cleanupStale()
        let work = FileManager.default.temporaryDirectory.appendingPathComponent(workPrefix + UUID().uuidString)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        do {
            let dmg = work.appendingPathComponent(dmgAsset)
            let sig = String(decoding: try curl(sigURL, timeout: 30), as: UTF8.self)
            _ = try curl(dmgURL, to: dmg, timeout: 600)
            guard verifyReleaseSignature(try Data(contentsOf: dmg), sig) else { throw UpdateError("sig_invalid") }

            let mnt = work.appendingPathComponent("mnt")
            try FileManager.default.createDirectory(at: mnt, withIntermediateDirectories: false)
            let appName = Bundle.main.bundleURL.lastPathComponent
            let staged = work.appendingPathComponent(appName)
            do {
                defer { detach(mnt) }   // never leave the DMG mounted
                guard run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen",
                                               "-mountpoint", mnt.path, dmg.path]).status == 0
                else { throw UpdateError("dmg_open") }
                let src = mnt.appendingPathComponent(appName)
                guard FileManager.default.fileExists(atPath: src.path) else { throw UpdateError("no_app") }
                guard run("/usr/bin/ditto", [src.path, staged.path]).status == 0 else { throw UpdateError("copy") }
            }

            let info = NSDictionary(contentsOf: staged.appendingPathComponent("Contents/Info.plist")) ?? [:]
            guard info["CFBundleIdentifier"] as? String == bundleID else { throw UpdateError("other_app") }
            let got = info["CFBundleShortVersionString"] as? String ?? ""
            // The signature covers the DMG, this pins it to the advertised version:
            // an old signed DMG can't be replayed as a "new" release (downgrade).
            guard parseVersion(got) == parseVersion(release.version) else {
                throw UpdateError("version_mismatch", ["got": got, "expected": release.version])
            }
            guard run("/usr/bin/codesign", ["--verify", "--deep", staged.path]).status == 0 else {
                throw UpdateError("codesign")
            }
            try? FileManager.default.removeItem(at: dmg)
            return staged
        } catch {
            try? FileManager.default.removeItem(at: work)
            throw error
        }
    }

    // Waits for the running app to exit, swaps the bundle (with rollback), restarts.
    static let swapScript = #"""
    #!/bin/bash
    PID="$1"; TARGET="$2"; NEW="$3"; LABEL="$4"; LOG="$5"
    log() { echo "$(date '+%Y-%m-%d %H:%M:%S') update: $*" >> "$LOG"; }
    for _ in $(seq 1 60); do kill -0 "$PID" 2>/dev/null || break; sleep 0.5; done
    BACKUP="$TARGET.previous"
    rm -rf "$BACKUP"
    if mv "$TARGET" "$BACKUP" && /usr/bin/ditto "$NEW" "$TARGET"; then
        /usr/bin/xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null
        rm -rf "$BACKUP"
        log "nieuwe versie geïnstalleerd"
    else
        rm -rf "$TARGET"
        mv "$BACKUP" "$TARGET"
        log "vervangen mislukt, oude versie teruggezet"
    fi
    if /bin/launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
        /bin/launchctl kickstart -k "gui/$(id -u)/$LABEL"
    else
        /usr/bin/open "$TARGET"
    fi
    rm -rf "$(dirname "$NEW")"
    """#

    /// Start the swap script in its own session (so launchd doesn't kill it along
    /// with our LaunchAgent job); the caller must quit right after.
    static func launchSwap(staged: URL, target: URL, pid: pid_t, label: String, logFile: URL) throws {
        let script = staged.deletingLastPathComponent().appendingPathComponent("swap.sh")
        try swapScript.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)

        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        for fd: Int32 in 0...2 {
            posix_spawn_file_actions_addopen(&actions, fd, "/dev/null", fd == 0 ? O_RDONLY : O_WRONLY, 0)
        }
        let argv = ["/bin/bash", script.path, String(pid), target.path, staged.path, label, logFile.path]
        var cargs = argv.map { strdup($0) } + [nil]
        defer { cargs.forEach { free($0) } }
        var child: pid_t = 0
        let rc = posix_spawn(&child, "/bin/bash", &actions, &attr, &cargs, environ)
        guard rc == 0 else { throw POSIXError(POSIXErrorCode(rawValue: rc) ?? .EIO) }
    }
}
