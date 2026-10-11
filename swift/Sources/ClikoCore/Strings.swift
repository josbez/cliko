import Foundation

/// All user-facing text, from Resources/strings.json. Every key goes in both languages.
public struct Strings {
    public let table: [String: [String: String]]
    public let days: [String: [String]]
    public let months: [String: [String]]
    public let defaultLang: String

    public static let empty = Strings(table: [:], days: [:], months: [:], defaultLang: "en")

    public init(table: [String: [String: String]], days: [String: [String]], months: [String: [String]],
                defaultLang: String) {
        self.table = table
        self.days = days
        self.months = months
        self.defaultLang = defaultLang
    }

    public init(contentsOf url: URL) throws {
        try self.init(json: try Data(contentsOf: url))
    }

    public init(json data: Data) throws {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let table = obj["strings"] as? [String: [String: String]],
              let days = obj["days"] as? [String: [String]],
              let months = obj["months"] as? [String: [String]],
              let defaultLang = obj["default_lang"] as? String
        else { throw CocoaError(.fileReadCorruptFile) }
        self.init(table: table, days: days, months: months, defaultLang: defaultLang)
    }

    /// Unknown language falls back to the default, unknown key to the default
    /// language's text, then to the key itself. "{name}" is replaced from kw.
    public func t(_ key: String, _ lang: String, _ kw: [String: Any] = [:]) -> String {
        let fallback = table[defaultLang] ?? [:]
        var text = (table[lang] ?? fallback)[key] ?? fallback[key] ?? key
        for (name, value) in kw {
            text = text.replacingOccurrences(of: "{\(name)}", with: "\(value)")
        }
        return text
    }

    /// Sunday first, like Calendar's weekday.
    public func dayNames(_ lang: String) -> [String] { days[lang] ?? days[defaultLang] ?? [] }
    public func monthNames(_ lang: String) -> [String] { months[lang] ?? months[defaultLang] ?? [] }
}

/// macOS preferred languages -> "nl" or "en". Only the first (= the user's chosen) language counts.
public func languageFrom(_ preferred: [String]) -> String {
    guard let first = preferred.first?.lowercased() else { return "en" }
    let base = first.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? first
    return base == "nl" ? "nl" : "en"
}

// MARK: - Texts built from pickups

public func kindLabel(_ pickup: Pickup, _ strings: Strings, _ lang: String) -> String {
    guard pickup.kind == .other else { return strings.t("kind_" + pickup.kind.rawValue, lang) }
    let label = pickup.label.lowercased()
    return label.prefix(1).uppercased() + label.dropFirst()
}

/// "PMD", "PMD and paper", "PMD, paper and residual waste".
public func joinedLabels(_ pickups: [Pickup], _ strings: Strings, _ lang: String) -> String {
    var labels: [String] = []
    for p in pickups {
        let label = kindLabel(p, strings, lang)
        if !labels.contains(label) { labels.append(label) }
    }
    guard labels.count > 1, let last = labels.last else { return labels.first ?? "" }
    return labels.dropLast().joined(separator: ", ") + " " + strings.t("and", lang) + " " + last
}

/// "Today", "Tomorrow", or "Thu 15 Oct" / "do 15 okt".
public func whenLabel(_ day: Day, now: Date, _ strings: Strings, _ lang: String,
                      calendar: Calendar = .current) -> String {
    let today = Day(now, calendar: calendar)
    if day == today { return strings.t("today", lang) }
    if day == today.adding(days: 1, calendar: calendar) { return strings.t("tomorrow", lang) }
    let days = strings.dayNames(lang), months = strings.monthNames(lang)
    guard let noon = day.date(hour: 12, calendar: calendar), days.count == 7, months.count == 12 else {
        return day.description
    }
    let weekday = calendar.component(.weekday, from: noon)   // 1 = Sunday
    return "\(days[weekday - 1]) \(day.day) \(months[day.month - 1])"
}

public func reminderText(_ reminder: Reminder, _ strings: Strings, _ lang: String) -> (title: String, body: String) {
    (strings.t("reminder_title", lang, ["what": joinedLabels(reminder.pickups, strings, lang)]),
     strings.t("reminder_body", lang))
}
