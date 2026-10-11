import CryptoKit
import Foundation

// Updates: GitHub release check and signature verification, as in Usage Meter.
// Downloading and installing is glue in the app (Updater.swift).

public let updateAPIURL = URL(string: "https://api.github.com/repos/josbez/cliko/releases/latest")!
public let updateCheckInterval: TimeInterval = 24 * 3600
public let dmgAsset = "Cliko.dmg"
public let sigAsset = dmgAsset + ".sig"

/// Ed25519 public key for release signatures: the same key as Usage Meter, so
/// one private key (~/.config/claude-usage/release-signing-key.pem, never in
/// git) signs both apps.
public let updatePublicKeyHex = "cd50f6dc348c4c0b3170df3c4204cb6b7adabb92c11a798116127c02d207cc66"

public struct Release: Codable, Equatable {
    public let version: String
    public let htmlURL: String
    public let dmgURL: String
    public let sigURL: String
}

public struct UpdateState: Codable {
    public var lastCheck: Date?
    public var latest: Release?
    public var notifiedVersion: String?

    public init() {}
}

/// "v1.10.2" -> [1, 10, 2]; anything else (pre-releases, "dev") -> nil.
public func parseVersion(_ v: String) -> [Int]? {
    var s = v.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
    let parts = s.split(separator: ".", omittingEmptySubsequences: false)
    guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } })
    else { return nil }
    var nums = parts.compactMap { Int($0) }
    while nums.count > 1 && nums.last == 0 { nums.removeLast() }   // 1.2 == 1.2.0
    return nums
}

public func isNewer(_ candidate: String, than current: String) -> Bool {
    guard let c = parseVersion(candidate), let cur = parseVersion(current) else { return false }
    return c != cur && !c.lexicographicallyPrecedes(cur)
}

/// What we need from a GitHub releases/latest response, or nil.
public func parseRelease(_ data: Data) -> Release? {
    guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          o["draft"] as? Bool != true, o["prerelease"] as? Bool != true,
          let tag = o["tag_name"] as? String, parseVersion(tag) != nil else { return nil }
    var assets: [String: String] = [:]
    for case let a as [String: Any] in o["assets"] as? [Any] ?? [] {
        if let name = a["name"] as? String { assets[name] = a["browser_download_url"] as? String ?? "" }
    }
    let version = String(tag.drop(while: { $0 == "v" || $0 == "V" }))
    return Release(version: version, htmlURL: o["html_url"] as? String ?? "",
                   dmgURL: assets[dmgAsset] ?? "", sigURL: assets[sigAsset] ?? "")
}

public func updateCheckDue(_ state: UpdateState, now: Date, interval: TimeInterval = updateCheckInterval) -> Bool {
    guard let last = state.lastCheck else { return true }
    return now.timeIntervalSince(last) >= interval
}

/// Base64 Ed25519 signature over the whole file.
public func verifyReleaseSignature(_ data: Data, _ sigText: String,
                                   publicKeyHex: String = updatePublicKeyHex) -> Bool {
    let b64 = sigText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let keyBytes = hexData(publicKeyHex),
          let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyBytes),
          b64.range(of: #"^[A-Za-z0-9+/]*={0,2}$"#, options: .regularExpression) != nil,
          let sig = Data(base64Encoded: b64)
    else { return false }
    return key.isValidSignature(sig, for: data)
}

public func hexData(_ s: String) -> Data? {
    guard s.count % 2 == 0 else { return nil }
    var data = Data()
    var i = s.startIndex
    while i < s.endIndex {
        let j = s.index(i, offsetBy: 2)
        guard let b = UInt8(s[i..<j], radix: 16) else { return nil }
        data.append(b)
        i = j
    }
    return data
}

/// An update failure: a strings.json key (without "upd_") plus values, so the
/// app can show it in the user's language.
public struct UpdateError: Error, CustomStringConvertible {
    public let key: String
    public let values: [String: Any]

    public init(_ key: String, _ values: [String: Any] = [:]) {
        self.key = key
        self.values = values
    }

    public func message(_ strings: Strings, _ lang: String) -> String {
        strings.t("upd_" + key, lang, values)
    }

    public var description: String { "\(key) \(values)" }
}

// MARK: - Signing releases

/// The 32-byte Ed25519 seed from a PKCS#8 PEM ("BEGIN PRIVATE KEY"); nil for anything else.
public func ed25519Seed(fromPEM pem: String) -> Data? {
    let body = pem.components(separatedBy: .newlines).filter { !$0.hasPrefix("-----") }.joined()
    guard pem.contains("-----BEGIN PRIVATE KEY-----"), let der = Data(base64Encoded: body) else { return nil }
    // SEQUENCE { INTEGER 0, SEQUENCE { OID 1.3.101.112 }, OCTET STRING { OCTET STRING (32) } }
    let prefix = Data([0x30, 0x2e, 0x02, 0x01, 0x00, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70,
                       0x04, 0x22, 0x04, 0x20])
    guard der.count == prefix.count + 32, der.prefix(prefix.count) == prefix else { return nil }
    return der.suffix(32)
}

public enum SignReleaseError: Error, CustomStringConvertible {
    case badKey, wrongKey, selfCheckFailed
    public var description: String {
        switch self {
        case .badKey: return "signing key onleesbaar (verwacht een Ed25519 PKCS#8 PEM)"
        case .wrongKey: return "signing key hoort niet bij updatePublicKeyHex — bestaande installaties zouden deze update weigeren"
        case .selfCheckFailed: return "zelfcontrole van de handtekening faalde"
        }
    }
}

/// Base64 Ed25519 signature over `data`, only with the key that matches the
/// public key installed apps check against.
public func signRelease(_ data: Data, pem: String, publicKeyHex: String = updatePublicKeyHex) throws -> String {
    guard let seed = ed25519Seed(fromPEM: pem),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: seed) else { throw SignReleaseError.badKey }
    let pub = key.publicKey.rawRepresentation.map { String(format: "%02x", $0) }.joined()
    guard pub == publicKeyHex.lowercased() else { throw SignReleaseError.wrongKey }
    let sig = try key.signature(for: data).base64EncodedString()
    guard verifyReleaseSignature(data, sig, publicKeyHex: publicKeyHex) else { throw SignReleaseError.selfCheckFailed }
    return sig
}
