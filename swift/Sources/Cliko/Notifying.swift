import AppKit
import ClikoCore
import UserNotifications

/// Reminders are scheduled with macOS ahead of time (calendar triggers), so
/// they fire on time without a timer of our own. Rescheduled after every
/// fetch: a collection that moves for a holiday moves its reminder too.
extension AppDelegate {
    func setupNotifications() {
        guard isBundled else { return }   // UNUserNotificationCenter needs a bundle
        let center = UNUserNotificationCenter.current()
        center.delegate = notifyDelegate
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            DispatchQueue.main.async {
                self?.log("notificatie-toestemming: \(granted ? "ja" : "nee")"
                          + (error.map { " (\($0.localizedDescription))" } ?? ""))
            }
        }
        scheduleReminders()
    }

    func scheduleReminders() {
        guard isBundled else { return }
        let center = UNUserNotificationCenter.current()
        let list = settings.reminders && cache?.matches(settings) == true
            ? reminders(for: cache?.pickups ?? [], hour: settings.reminderHour, minute: settings.reminderMinute,
                        now: Date(), calendar: calendar)
            : []
        let cal = calendar
        let requests = list.map { r -> UNNotificationRequest in
            let text = reminderText(r, strings, lang)
            let content = UNMutableNotificationContent()
            content.title = (isDev ? "β " : "") + text.title
            content.body = text.body
            content.sound = .default
            let when = cal.dateComponents([.year, .month, .day, .hour, .minute], from: r.fire)
            return UNNotificationRequest(identifier: r.id, content: content,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false))
        }
        center.getPendingNotificationRequests { [weak self] pending in
            let old = pending.map(\.identifier).filter { $0.hasPrefix(reminderIDPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: old)
            for request in requests {
                center.add(request) { error in
                    guard let error else { return }
                    DispatchQueue.main.async { self?.log("herinnering plannen mislukt: \(error.localizedDescription)") }
                }
            }
            DispatchQueue.main.async { self?.log("\(requests.count) herinneringen gepland") }
        }
    }

    /// A one-off notification right now (update available).
    func post(id: String, title: String, body: String) {
        guard isBundled else { return }
        let content = UNMutableNotificationContent()
        content.title = (isDev ? "β " : "") + title
        content.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
        log("notificatie: \(title)")
    }
}

/// Show banners even while Cliko is the active app (menu open, alert shown).
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completion: @escaping (UNNotificationPresentationOptions) -> Void) {
        completion([.banner, .list, .sound])
    }
}
