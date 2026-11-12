// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CleanerCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CleanerCore", targets: ["CleanerCore"]),
    ],
    dependencies: [
        // SQLite storage for scan history, exclusions and the action log.
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        // All scan/clean logic lives here. No SwiftUI or AppKit imports allowed.
        .target(
            name: "CleanerCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(name: "CleanerCoreTests", dependencies: ["CleanerCore"]),
    ]
)
