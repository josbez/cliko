import Foundation

/// On a collection day the icon moves on to the next collection at noon: by
/// then the bin has been emptied, and Wednesday evening should already show
/// Thursday's bin.
public let pickupDayCutoffHour = 12

/// The next moment the icon moves on: today at the cutoff hour, or tomorrow's
/// once that has passed. The app redraws exactly then, not at its next check.
public func nextCutoff(after now: Date, calendar: Calendar = .current) -> Date? {
    let today = Day(now, calendar: calendar)
    guard let todays = today.date(hour: pickupDayCutoffHour, minute: 0, calendar: calendar) else { return nil }
    if todays > now { return todays }
    return today.adding(days: 1, calendar: calendar)?.date(hour: pickupDayCutoffHour, minute: 0, calendar: calendar)
}

/// Pickups still to come, sorted.
public func upcomingPickups(_ pickups: [Pickup], now: Date, calendar: Calendar = .current) -> [Pickup] {
    let today = Day(now, calendar: calendar)
    let beforeCutoff = calendar.component(.hour, from: now) < pickupDayCutoffHour
    return pickups.filter { $0.day > today || ($0.day == today && beforeCutoff) }.sorted()
}

/// Everything on the first upcoming day; the first one is the menu bar icon.
public func nextPickups(_ upcoming: [Pickup]) -> [Pickup] {
    guard let first = upcoming.min() else { return [] }
    return upcoming.filter { $0.day == first.day }.sorted()
}

// MARK: - Reminders

public let reminderIDPrefix = "cliko-reminder-"

/// One notification the evening before a collection day, for all bins of that day.
public struct Reminder: Equatable {
    public let id: String
    public let fire: Date
    public let pickups: [Pickup]
}

/// Reminders that still lie ahead, within the horizon (macOS keeps at most 64
/// pending notifications; five weeks is about ten).
public func reminders(for pickups: [Pickup], hour: Int, minute: Int, now: Date, horizonDays: Int = 35,
                      calendar: Calendar = .current) -> [Reminder] {
    let byDay = Dictionary(grouping: pickups, by: \.day)
    let horizon = now.addingTimeInterval(TimeInterval(horizonDays) * 86_400)
    return byDay.keys.sorted().compactMap { day in
        guard let eve = day.adding(days: -1, calendar: calendar),
              let fire = eve.date(hour: hour, minute: minute, calendar: calendar),
              fire > now, fire <= horizon else { return nil }
        return Reminder(id: reminderIDPrefix + day.description, fire: fire, pickups: (byDay[day] ?? []).sorted())
    }
}

// MARK: - Storage of the fetched calendar

public struct CalendarCache: Codable, Equatable {
    public let postcode: String
    public let houseNumber: String
    public let fetchedAt: Date
    public let pickups: [Pickup]

    public init(postcode: String, houseNumber: String, fetchedAt: Date, pickups: [Pickup]) {
        self.postcode = postcode
        self.houseNumber = houseNumber
        self.fetchedAt = fetchedAt
        self.pickups = pickups
    }

    public func matches(_ settings: Settings) -> Bool {
        postcode == settings.postcode && houseNumber == settings.houseNumber
    }
}

/// Twice a day picks up shifted dates (holidays) well before the evening reminder.
public let calendarRefreshInterval: TimeInterval = 12 * 3600
public let fetchRetryInterval: TimeInterval = 30 * 60

public func fetchDue(cache: CalendarCache?, settings: Settings, lastFailure: Date?, now: Date) -> Bool {
    guard settings.hasAddress else { return false }
    if let lastFailure, now.timeIntervalSince(lastFailure) < fetchRetryInterval { return false }
    guard let cache, cache.matches(settings) else { return true }
    return now.timeIntervalSince(cache.fetchedAt) >= calendarRefreshInterval
}
