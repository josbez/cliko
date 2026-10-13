import Foundation

/// Ximmio's waste API, as used by RAD (Hoeksche Waard, Goeree-Overflakkee).
/// Two form-encoded POSTs: FetchAdress (postcode + house number -> address id),
/// then GetCalendar (address id + date range -> pickup dates per waste type).
/// Endpoint and company code as in hacs_waste_collection_schedule's ximmio_nl source.
public enum Ximmio {
    public static let baseURL = URL(string: "https://wasteprod2api.ximmio.com")!
    /// RAD BV
    public static let companyCode = "13a2cad9-36d0-4b01-b877-efcb421a864d"

    public static func addressRequest(postcode: String, houseNumber: String) -> URLRequest {
        request("FetchAdress", [("postCode", postcode), ("houseNumber", houseNumber), ("companyCode", companyCode)])
    }

    public static func calendarRequest(address: XimmioAddress, from: Day, to: Day) -> URLRequest {
        request("GetCalendar", [("uniqueAddressID", address.uniqueId), ("startDate", from.description),
                                ("endDate", to.description), ("companyCode", companyCode),
                                ("community", address.community)])
    }

    static func request(_ endpoint: String, _ fields: [(String, String)]) -> URLRequest {
        var r = URLRequest(url: baseURL.appendingPathComponent("api").appendingPathComponent(endpoint),
                           timeoutInterval: 20)
        r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        r.httpBody = formBody(fields)
        return r
    }

    public static func formBody(_ fields: [(String, String)]) -> Data {
        let allowed = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: allowed) ?? "" }
        return Data(fields.map { "\(enc($0.0))=\(enc($0.1))" }.joined(separator: "&").utf8)
    }

    /// The first address in the answer (a house number with additions returns several).
    public static func parseAddress(_ data: Data) throws -> XimmioAddress {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw XimmioError.badResponse
        }
        let list = obj["dataList"] as? [[String: Any]] ?? []
        guard let first = list.first, let id = first["UniqueId"] as? String, !id.isEmpty else {
            throw XimmioError.addressNotFound
        }
        return XimmioAddress(uniqueId: id, community: first["Community"] as? String ?? "")
    }

    /// All pickups in the answer, sorted, duplicates removed. Unknown waste
    /// types are kept as `.other`; dates that don't parse are skipped.
    public static func parseCalendar(_ data: Data) throws -> [Pickup] {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let list = obj["dataList"] as? [[String: Any]] else { throw XimmioError.badResponse }
        var out = Set<Pickup>()
        for item in list {
            let code = item["_pickupTypeText"] as? String ?? ""
            // RAD sends the literal string "Null" when there is no description
            let description = (item["description"] as? String)
                .flatMap { $0.isEmpty || $0.lowercased() == "null" ? nil : $0 } ?? code
            let kind = WasteKind(ximmioCode: code)
            for s in item["pickupDates"] as? [String] ?? [] {
                if let day = Day(iso: s) { out.insert(Pickup(day: day, kind: kind, label: description, code: code)) }
            }
        }
        return out.sorted()
    }
}

public struct XimmioAddress: Codable, Equatable {
    public let uniqueId: String
    public let community: String

    public init(uniqueId: String, community: String) {
        self.uniqueId = uniqueId
        self.community = community
    }
}

public enum XimmioError: Error, Equatable {
    case badResponse, addressNotFound, http(Int)

    /// strings.json key for the message.
    public var stringKey: String {
        switch self {
        case .badResponse, .http: return "err_bad_response"
        case .addressNotFound: return "err_address_not_found"
        }
    }
}

public struct XimmioClient {
    public var session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func address(postcode: String, houseNumber: String) async throws -> XimmioAddress {
        try Ximmio.parseAddress(try await post(Ximmio.addressRequest(postcode: postcode, houseNumber: houseNumber)))
    }

    public func pickups(address: XimmioAddress, from: Day, to: Day) async throws -> [Pickup] {
        try Ximmio.parseCalendar(try await post(Ximmio.calendarRequest(address: address, from: from, to: to)))
    }

    func post(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw XimmioError.http(status) }
        return data
    }
}
