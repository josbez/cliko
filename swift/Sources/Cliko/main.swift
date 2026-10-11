import AppKit
import ClikoCore

let args = CommandLine.arguments

final class Box<T> {
    var value: T
    init(_ value: T) { self.value = value }
}

// Check the data source without the UI: address lookup and the next 60 days.
//   Cliko --probe <postcode> <huisnummer>
if args.count == 4, args[1] == "--probe" {
    guard let postcode = normalizePostcode(args[2]), let number = normalizeHouseNumber(args[3]) else {
        print("✗ ongeldige postcode of huisnummer")
        exit(1)
    }
    let status = Box<Int32>(0)
    let done = DispatchSemaphore(value: 0)
    Task.detached {
        do {
            let client = XimmioClient()
            let address = try await client.address(postcode: postcode, houseNumber: number)
            print("✓ adres gevonden (community: \(address.community.isEmpty ? "-" : address.community))")
            let today = Day(Date())
            let pickups = try await client.pickups(address: address, from: today,
                                                   to: today.adding(days: 60) ?? today)
            for p in pickups { print("  \(p.day)  \(p.kind.rawValue)\t(\(p.label))") }
            print("✓ \(pickups.count) ophaaldagen in de komende 60 dagen")
        } catch {
            print("✗ \(error)")
            status.value = 1
        }
        done.signal()
    }
    done.wait()
    exit(status.value)
}

// Check a release file against its .sig with the release key:
//   Cliko --verify-release <file> <file.sig>
if args.count == 4, args[1] == "--verify-release",
   let data = FileManager.default.contents(atPath: args[2]),
   let sig = try? String(contentsOfFile: args[3], encoding: .utf8) {
    let ok = verifyReleaseSignature(data, sig)
    print(ok ? "✓ handtekening geldig" : "✗ handtekening ongeldig")
    exit(ok ? 0 : 1)
}

// Sign a release file with the key shared with Usage Meter (never in git):
//   Cliko --sign-release <file>   → <file>.sig
if args.count == 3, args[1] == "--sign-release" {
    let keyFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/claude-usage/release-signing-key.pem")
    guard let pem = try? String(contentsOf: keyFile, encoding: .utf8) else {
        print("✗ geen signing key in \(keyFile.path)")
        exit(1)
    }
    guard let data = FileManager.default.contents(atPath: args[2]) else {
        print("✗ \(args[2]) niet gevonden")
        exit(1)
    }
    do {
        let sig = try signRelease(data, pem: pem)
        try (sig + "\n").write(toFile: args[2] + ".sig", atomically: true, encoding: .utf8)
        print("✓ \((args[2] as NSString).lastPathComponent).sig aangemaakt en geverifieerd")
        exit(0)
    } catch {
        print("✗ \(error)")
        exit(1)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // menu bar only, no Dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()
