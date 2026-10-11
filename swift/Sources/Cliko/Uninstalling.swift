import AppKit
import ClikoCore
import UserNotifications

/// "Uninstall…": own files, pending reminders, the app to the Trash, the
/// LaunchAgent, and as the very last step booting the agent out (that stops us).
extension AppDelegate {
    @objc func confirmUninstall() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = t("alert_uninstall_title")
        alert.informativeText = t("alert_uninstall_body")
        let confirm = alert.addButton(withTitle: t("btn_uninstall"))
        confirm.hasDestructiveAction = true
        alert.addButton(withTitle: t("btn_cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        uninstall()
    }

    private func uninstall() {
        log("verwijderen gestart")
        timer?.invalidate()
        if isBundled {
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        }
        let fm = FileManager.default
        for url in paths.uninstallTargets where fm.fileExists(atPath: url.path) {
            try? fm.removeItem(at: url)
        }
        // From here on log() would recreate the log file: stay quiet unless it fails.
        NSWorkspace.shared.recycle([Bundle.main.bundleURL]) { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    let alert = NSAlert()
                    alert.messageText = self.t("alert_uninstall_failed_title")
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                    return
                }
                if let plist = self.paths.launchAgent, fm.fileExists(atPath: plist.path) {
                    try? fm.removeItem(at: plist)
                }
                if !self.isDev {
                    // KeepAlive is false: bootout stops this process and launchd won't restart it.
                    let p = Process()
                    p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
                    p.arguments = ["bootout", "gui/\(getuid())/\(Paths.launchAgentLabel)"]
                    try? p.run()
                    p.waitUntilExit()
                }
                NSApp.terminate(nil)   // not started by launchd, or bootout didn't stop us
            }
        }
    }
}
