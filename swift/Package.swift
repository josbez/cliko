// swift-tools-version:5.9
// Cliko. ClikoCore = pure logic (Foundation only, XCTest); Cliko = AppKit glue.
import PackageDescription

let package = Package(
    name: "Cliko",
    platforms: [.macOS(.v12)],
    targets: [
        .target(name: "ClikoCore"),
        .executableTarget(name: "Cliko", dependencies: ["ClikoCore"]),
        .testTarget(
            name: "ClikoCoreTests",
            dependencies: ["ClikoCore"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
