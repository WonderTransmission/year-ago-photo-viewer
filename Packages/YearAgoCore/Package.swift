// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "YearAgoCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "YearAgoCore", targets: ["YearAgoCore"]),
        // Small library shared by the app and the widget extension: the
        // widget snapshot format, deep links, and the App Group folder.
        .library(name: "YearAgoSnapshot", targets: ["YearAgoSnapshot"]),
    ],
    targets: [
        .target(name: "YearAgoCore"),
        .target(name: "YearAgoSnapshot"),
        .testTarget(name: "YearAgoCoreTests", dependencies: ["YearAgoCore", "YearAgoSnapshot"]),
    ]
)
