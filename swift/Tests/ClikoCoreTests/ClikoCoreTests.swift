import XCTest
@testable import ClikoCore

/// Amsterdam time, whatever the test machine's zone.
let amsterdam: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
    return c
}()

func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    amsterdam.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

func fixture(_ name: String) throws -> Data {
    let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

func loadStrings() throws -> Strings {
    // Tests/ClikoCoreTests/ -> swift/Resources/strings.json
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Resources/strings.json")
    return try Strings(contentsOf: url)
}

final class XimmioTests: XCTestCase {
    func testParsesAddress() throws {
        let address = try Ximmio.parseAddress(try fixture("address"))
        XCTAssertEqual(address, XimmioAddress(uniqueId: "1234567", community: "Goeree-Overflakkee"))
    }

    func testAddressNotFound() throws {
        XCTAssertThrowsError(try Ximmio.parseAddress(try fixture("address-not-found"))) {
            XCTAssertEqual($0 as? XimmioError, .addressNotFound)
        }
        XCTAssertThrowsError(try Ximmio.parseAddress(Data("<html>".utf8))) {
            XCTAssertEqual($0 as? XimmioError, .badResponse)
        }
    }

    func testParsesCalendarSortedWithKinds() throws {
        let pickups = try Ximmio.parseCalendar(try fixture("calendar"))
        XCTAssertEqual(pickups.count, 12)   // 5 PMD + 2 GFT + 1 paper + 2 rest + 1 tree (bad date skipped) + 1 KCA
        XCTAssertEqual(pickups.first, Pickup(day: Day(year: 2026, month: 9, day: 30), kind: .pmd, label: "PACKAGES"))
        XCTAssertEqual(pickups.map(\.day), pickups.map(\.day).sorted())
        XCTAssertEqual(pickups.first { $0.day == Day(year: 2026, month: 10, day: 15) }?.kind, .paper)
        // "Null" description falls back to the type code
        XCTAssertEqual(pickups.first { $0.label == "KCA" }?.kind, .other)
        XCTAssertEqual(pickups.first { $0.kind == .tree }?.label, "Kerstbomen")
        XCTAssertEqual(pickups.last?.kind, .tree)
    }

    func testCalendarWithoutDataListIsBadResponse() {
        XCTAssertThrowsError(try Ximmio.parseCalendar(Data(#"{"status":false}"#.utf8))) {
            XCTAssertEqual($0 as? XimmioError, .badResponse)
        }
    }

    func testRequests() throws {
        let address = Ximmio.addressRequest(postcode: "3241AB", houseNumber: "12")
        XCTAssertEqual(address.url?.absoluteString, "https://wasteprod2api.ximmio.com/api/FetchAdress")
        XCTAssertEqual(address.httpMethod, "POST")
        XCTAssertEqual(String(decoding: try XCTUnwrap(address.httpBody), as: UTF8.self),
                       "postCode=3241AB&houseNumber=12&companyCode=13a2cad9-36d0-4b01-b877-efcb421a864d")

        let calendar = Ximmio.calendarRequest(address: XimmioAddress(uniqueId: "1234567", community: "Goeree-Overflakkee"),
                                              from: Day(year: 2026, month: 10, day: 9),
                                              to: Day(year: 2027, month: 10, day: 10))
        XCTAssertEqual(calendar.url?.absoluteString, "https://wasteprod2api.ximmio.com/api/GetCalendar")
        XCTAssertEqual(String(decoding: try XCTUnwrap(calendar.httpBody), as: UTF8.self),
                       "uniqueAddressID=1234567&startDate=2026-10-09&endDate=2027-10-10"
                       + "&companyCode=13a2cad9-36d0-4b01-b877-efcb421a864d&community=Goeree-Overflakkee")
    }

    func testFormBodyEscapes() {
        XCTAssertEqual(String(decoding: Ximmio.formBody([("a b", "x&y=z/ü")]), as: UTF8.self), "a%20b=x%26y%3Dz%2F%C3%BC")
    }

    func testKindCodes() {
        XCTAssertEqual(WasteKind(ximmioCode: "GREY"), .rest)
        XCTAssertEqual(WasteKind(ximmioCode: "green"), .gft)
        XCTAssertEqual(WasteKind(ximmioCode: "PAPER"), .paper)
        XCTAssertEqual(WasteKind(ximmioCode: "PACKAGES"), .pmd)
        XCTAssertEqual(WasteKind(ximmioCode: "PLASTIC"), .pmd)
        XCTAssertEqual(WasteKind(ximmioCode: "TEXTILE"), .textile)
        XCTAssertEqual(WasteKind(ximmioCode: "SOMETHING"), .other)
    }
}

final class ScheduleTests: XCTestCase {
    var pickups: [Pickup] = []

    override func setUpWithError() throws {
        pickups = try Ximmio.parseCalendar(try fixture("calendar"))
    }

    func next(_ now: Date) -> [Pickup] { nextPickups(upcomingPickups(pickups, now: now, calendar: amsterdam)) }

    func testSaturdayShowsWednesdayPMD() {
        XCTAssertEqual(next(at(2026, 10, 10, 18, 23)).map(\.kind), [.pmd])
        XCTAssertEqual(next(at(2026, 10, 10, 18, 23)).first?.day, Day(year: 2026, month: 10, day: 14))
    }

    func testPickupDaySwitchesAtNoon() {
        XCTAssertEqual(next(at(2026, 10, 14, 7, 0)).map(\.kind), [.pmd])
        XCTAssertEqual(next(at(2026, 10, 14, 11, 59)).map(\.kind), [.pmd])
        XCTAssertEqual(next(at(2026, 10, 14, 12, 0)).map(\.kind), [.paper])   // Wednesday afternoon: Thursday's bin
        XCTAssertEqual(next(at(2026, 10, 15, 13, 0)).map(\.kind), [.pmd])
    }

    func testSameDayKeepsKindOrder() {
        let day = Day(year: 2026, month: 12, day: 24)
        let both = [Pickup(day: day, kind: .pmd, label: "PMD"), Pickup(day: day, kind: .rest, label: "Rest")]
        XCTAssertEqual(nextPickups(upcomingPickups(both, now: at(2026, 12, 20), calendar: amsterdam)).map(\.kind),
                       [.rest, .pmd])
    }

    func testNothingLeft() {
        XCTAssertTrue(next(at(2027, 2, 1)).isEmpty)
    }

    func testRemindersEveningBefore() {
        let list = reminders(for: pickups, hour: 19, minute: 0, now: at(2026, 10, 10, 18, 23), calendar: amsterdam)
        XCTAssertEqual(list.first?.id, "cliko-reminder-2026-10-14")
        XCTAssertEqual(list.first?.fire, at(2026, 10, 13, 19, 0))
        XCTAssertEqual(list.dropFirst().first?.fire, at(2026, 10, 14, 19, 0))
        XCTAssertEqual(list.dropFirst().first?.pickups.map(\.kind), [.paper])
        // 35-day horizon: nothing for the tree in January
        XCTAssertFalse(list.contains { $0.pickups.contains { $0.kind == .tree } })
    }

    func testRemindersSkipThePast() {
        // 13 Oct 19:30: the reminder for the 14th has fired already
        let list = reminders(for: pickups, hour: 19, minute: 0, now: at(2026, 10, 13, 19, 30), calendar: amsterdam)
        XCTAssertEqual(list.first?.id, "cliko-reminder-2026-10-15")
    }

    func testReminderAcrossDSTChange() {
        // Clocks go back on Sunday 25 Oct 2026; Monday's reminder is Sunday 19:00 local
        let monday = [Pickup(day: Day(year: 2026, month: 10, day: 26), kind: .gft, label: "GFT")]
        let list = reminders(for: monday, hour: 19, minute: 0, now: at(2026, 10, 20), calendar: amsterdam)
        XCTAssertEqual(list.first?.fire, at(2026, 10, 25, 19, 0))
    }

    func testFetchDue() {
        var settings = Settings()
        let now = at(2026, 10, 10, 12)
        XCTAssertFalse(fetchDue(cache: nil, settings: settings, lastFailure: nil, now: now))
        settings.postcode = "3241AB"
        settings.houseNumber = "12"
        XCTAssertTrue(fetchDue(cache: nil, settings: settings, lastFailure: nil, now: now))
        XCTAssertFalse(fetchDue(cache: nil, settings: settings, lastFailure: now.addingTimeInterval(-60), now: now))
        let fresh = CalendarCache(postcode: "3241AB", houseNumber: "12", fetchedAt: now.addingTimeInterval(-3600), pickups: [])
        XCTAssertFalse(fetchDue(cache: fresh, settings: settings, lastFailure: nil, now: now))
        let old = CalendarCache(postcode: "3241AB", houseNumber: "12", fetchedAt: now.addingTimeInterval(-13 * 3600), pickups: [])
        XCTAssertTrue(fetchDue(cache: old, settings: settings, lastFailure: nil, now: now))
        let elsewhere = CalendarCache(postcode: "3241AB", houseNumber: "14", fetchedAt: now, pickups: [])
        XCTAssertTrue(fetchDue(cache: elsewhere, settings: settings, lastFailure: nil, now: now))
    }
}

final class TextTests: XCTestCase {
    func testReminderTitles() throws {
        let strings = try loadStrings()
        let day = Day(year: 2026, month: 10, day: 15)
        let one = Reminder(id: "x", fire: Date(), pickups: [Pickup(day: day, kind: .paper, label: "Container oud papier")])
        XCTAssertEqual(reminderText(one, strings, "nl").title, "Morgen: Oud papier")
        let three = Reminder(id: "x", fire: Date(), pickups: [
            Pickup(day: day, kind: .rest, label: ""), Pickup(day: day, kind: .pmd, label: ""),
            Pickup(day: day, kind: .other, label: "KLEIN CHEMISCH AFVAL"),
        ])
        XCTAssertEqual(reminderText(three, strings, "nl").title, "Morgen: Restafval, PMD en Klein chemisch afval")
        XCTAssertEqual(reminderText(three, strings, "en").title,
                       "Tomorrow: Residual waste, Plastic & cans and Klein chemisch afval")
    }

    func testWhenLabels() throws {
        let strings = try loadStrings()
        let now = at(2026, 10, 10, 18)
        XCTAssertEqual(whenLabel(Day(year: 2026, month: 10, day: 10), now: now, strings, "nl", calendar: amsterdam), "Vandaag")
        XCTAssertEqual(whenLabel(Day(year: 2026, month: 10, day: 11), now: now, strings, "nl", calendar: amsterdam), "Morgen")
        XCTAssertEqual(whenLabel(Day(year: 2026, month: 10, day: 15), now: now, strings, "nl", calendar: amsterdam), "do 15 okt")
        XCTAssertEqual(whenLabel(Day(year: 2026, month: 10, day: 15), now: now, strings, "en", calendar: amsterdam), "Thu 15 Oct")
    }

    func testEveryKeyInBothLanguages() throws {
        let strings = try loadStrings()
        XCTAssertEqual(Set((strings.table["nl"] ?? [:]).keys), Set((strings.table["en"] ?? [:]).keys))
        for kind in WasteKind.allCases where kind != .other {
            XCTAssertNotNil(strings.table["nl"]?["kind_" + kind.rawValue], kind.rawValue)
        }
    }

    func testLanguage() {
        XCTAssertEqual(languageFrom(["nl-NL", "en-US"]), "nl")
        XCTAssertEqual(languageFrom(["en-NL", "nl-NL"]), "en")
        XCTAssertEqual(languageFrom([]), "en")
    }
}

final class SettingsTests: XCTestCase {
    func testPostcodeAndHouseNumber() {
        XCTAssertEqual(normalizePostcode(" 3241 ab "), "3241AB")
        XCTAssertNil(normalizePostcode("0241AB"))
        XCTAssertNil(normalizePostcode("3241A"))
        XCTAssertEqual(formatPostcode("3241AB"), "3241 AB")
        XCTAssertEqual(normalizeHouseNumber("12"), "12")
        XCTAssertEqual(normalizeHouseNumber(" 12a"), "12")
        XCTAssertNil(normalizeHouseNumber("a12"))
        XCTAssertNil(normalizeHouseNumber(""))
    }

    func testOldSettingsFileKeepsDefaults() throws {
        let s = try JSONDecoder().decode(Settings.self, from: Data(#"{"postcode":"3241AB"}"#.utf8))
        XCTAssertEqual(s.postcode, "3241AB")
        XCTAssertNil(s.houseNumber)
        XCTAssertTrue(s.reminders)
        XCTAssertEqual(s.reminderHour, 19)
        XCTAssertFalse(s.hasAddress)
    }

    func testCacheRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = CalendarCache(postcode: "3241AB", houseNumber: "12", fetchedAt: Date(timeIntervalSince1970: 1_800_000_000),
                                  pickups: [Pickup(day: Day(year: 2026, month: 10, day: 14), kind: .pmd, label: "PMD zak")])
        let url = dir.appendingPathComponent("calendar.json")
        try saveJSON(cache, to: url)
        XCTAssertEqual(loadJSON(CalendarCache.self, from: url), cache)
        XCTAssertTrue(String(decoding: try Data(contentsOf: url), as: UTF8.self).contains(#""day" : "2026-10-14""#))
    }
}

final class UpdateTests: XCTestCase {
    func testVersions() {
        XCTAssertEqual(parseVersion("v1.10.2"), [1, 10, 2])
        XCTAssertEqual(parseVersion("1.2.0"), [1, 2])
        XCTAssertNil(parseVersion("1.2-beta"))
        XCTAssertTrue(isNewer("1.10", than: "1.9"))
        XCTAssertFalse(isNewer("1.0", than: "1.0.0"))
        XCTAssertFalse(isNewer("0.9", than: "1.0"))
    }

    func testParseRelease() throws {
        let json = #"""
        {"tag_name":"v1.1","html_url":"https://github.com/josbez/cliko/releases/tag/v1.1","draft":false,"prerelease":false,
         "assets":[{"name":"Cliko.dmg","browser_download_url":"https://x/Cliko.dmg"},
                   {"name":"Cliko.dmg.sig","browser_download_url":"https://x/Cliko.dmg.sig"}]}
        """#
        let r = try XCTUnwrap(parseRelease(Data(json.utf8)))
        XCTAssertEqual(r.version, "1.1")
        XCTAssertEqual(r.dmgURL, "https://x/Cliko.dmg")
        XCTAssertEqual(r.sigURL, "https://x/Cliko.dmg.sig")
        XCTAssertNil(parseRelease(Data(#"{"tag_name":"v1.2","prerelease":true}"#.utf8)))
    }

    func testRejectsBadSignature() {
        XCTAssertFalse(verifyReleaseSignature(Data("x".utf8), "AAAA"))
        XCTAssertFalse(verifyReleaseSignature(Data("x".utf8), "not base64!"))
    }
}
