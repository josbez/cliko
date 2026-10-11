import Foundation

public struct Settings: Codable, Equatable {
    /// "3241AB": no space, upper case.
    public var postcode: String?
    /// Digits only (Ximmio's houseNumber).
    public var houseNumber: String?
    public var reminders = true
    public var reminderHour = 19
    public var reminderMinute = 0
    public var updateCheck = true
    /// "system" (follow macOS), "nl" or "en".
    public var language = "system"

    public init() {}

    /// Missing keys keep their default, so older settings files stay valid.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        postcode = try c.decodeIfPresent(String.self, forKey: .postcode)
        houseNumber = try c.decodeIfPresent(String.self, forKey: .houseNumber)
        reminders = try c.decodeIfPresent(Bool.self, forKey: .reminders) ?? true
        reminderHour = try c.decodeIfPresent(Int.self, forKey: .reminderHour) ?? 19
        reminderMinute = try c.decodeIfPresent(Int.self, forKey: .reminderMinute) ?? 0
        updateCheck = try c.decodeIfPresent(Bool.self, forKey: .updateCheck) ?? true
        language = try c.decodeIfPresent(String.self, forKey: .language) ?? "system"
    }

    public var hasAddress: Bool { postcode != nil && houseNumber != nil }
}

/// "3241 ab" -> "3241AB"; nil if it isn't a Dutch postcode.
public func normalizePostcode(_ s: String) -> String? {
    let compact = s.uppercased().filter { !$0.isWhitespace }
    guard compact.range(of: #"^[1-9][0-9]{3}[A-Z]{2}$"#, options: .regularExpression) != nil else { return nil }
    return compact
}

/// "3241AB" -> "3241 AB", for display.
public func formatPostcode(_ s: String) -> String {
    guard s.count == 6 else { return s }
    return "\(s.prefix(4)) \(s.suffix(2))"
}

/// The leading digits: "12" and "12a" -> "12". Ximmio returns all additions
/// for a number and Cliko takes the first, which shares the same calendar.
public func normalizeHouseNumber(_ s: String) -> String? {
    let digits = s.trimmingCharacters(in: .whitespaces).prefix { $0.isASCII && $0.isNumber }
    guard !digits.isEmpty, digits.first != "0", digits.count <= 5 else { return nil }
    return String(digits)
}

// MARK: - Files

public struct Paths {
    public static let launchAgentLabel = "com.jos.cliko"

    public let dev: Bool
    public let home: URL

    public init(dev: Bool, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.dev = dev
        self.home = home
    }

    public var support: URL {
        home.appendingPathComponent("Library/Application Support/" + (dev ? "Cliko Dev" : "Cliko"))
    }
    public var settings: URL { support.appendingPathComponent("settings.json") }
    public var calendar: URL { support.appendingPathComponent("calendar.json") }
    public var updateState: URL { support.appendingPathComponent("update.json") }
    public var log: URL { home.appendingPathComponent("Library/Logs/" + (dev ? "Cliko-Dev.log" : "Cliko.log")) }
    /// The dev build is started by hand, never by launchd.
    public var launchAgent: URL? {
        dev ? nil : home.appendingPathComponent("Library/LaunchAgents/\(Paths.launchAgentLabel).plist")
    }

    public var uninstallTargets: [URL] { [support, log] }
}

public func loadJSON<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try? decoder.decode(type, from: data)
}

public func saveJSON<T: Encodable>(_ value: T, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try encoder.encode(value).write(to: url, options: .atomic)
}
