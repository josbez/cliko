import Foundation

/// A calendar day without a time, in the user's own time zone.
public struct Day: Hashable, Comparable, Codable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(_ date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    /// "2026-10-14" or Ximmio's "2026-10-14T00:00:00".
    public init?(iso: String) {
        let parts = iso.prefix(10).split(separator: "-")
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        self.init(year: y, month: m, day: d)
    }

    public var description: String { String(format: "%04d-%02d-%02d", year, month, day) }

    public func date(hour: Int = 0, minute: Int = 0, calendar: Calendar = .current) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))
    }

    public func adding(days: Int, calendar: Calendar = .current) -> Day? {
        // From noon, so a DST change never lands on the wrong day
        guard let noon = date(hour: 12, calendar: calendar),
              let moved = calendar.date(byAdding: .day, value: days, to: noon) else { return nil }
        return Day(moved, calendar: calendar)
    }

    public static func < (a: Day, b: Day) -> Bool { (a.year, a.month, a.day) < (b.year, b.month, b.day) }

    public init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        guard let d = Day(iso: s) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "bad day \(s)"))
        }
        self = d
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(description)
    }
}

/// The kinds of waste the menu bar knows an icon for. The order is the
/// tie-break when two collections fall on the same day.
public enum WasteKind: String, CaseIterable, Codable {
    case rest, gft, paper, pmd, textile, tree, other

    /// Ximmio's `_pickupTypeText`. Unknown codes become `.other` and keep their own description.
    public init(ximmioCode: String) {
        switch ximmioCode.uppercased() {
        case "GREY", "REST": self = .rest
        case "GREEN", "GFT": self = .gft
        case "PAPER": self = .paper
        case "PACKAGES", "PLASTIC", "PMD": self = .pmd
        case "TEXTILE": self = .textile
        case "TREE": self = .tree
        default: self = .other
        }
    }

    /// SF Symbol, drawn as a template image (monochrome, tinted like the other
    /// menu bar icons). PMD has no fitting symbol; the app draws a bin bag and
    /// uses this one only where it can't.
    public var symbolName: String {
        switch self {
        case .rest: return "trash"
        case .gft: return "leaf"
        case .paper: return "newspaper"
        case .pmd: return "bag"
        case .textile: return "tshirt"
        case .tree: return "tree"
        case .other: return "shippingbox"
        }
    }

    var order: Int { Self.allCases.firstIndex(of: self) ?? Self.allCases.count }
}

public struct Pickup: Hashable, Codable, Comparable {
    public let day: Day
    public let kind: WasteKind
    /// Ximmio's own description; shown for `.other`.
    public let label: String

    public init(day: Day, kind: WasteKind, label: String) {
        self.day = day
        self.kind = kind
        self.label = label
    }

    public static func < (a: Pickup, b: Pickup) -> Bool {
        a.day != b.day ? a.day < b.day : a.kind.order < b.kind.order
    }
}
