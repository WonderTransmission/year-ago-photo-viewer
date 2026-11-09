// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "YearAgoCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "YearAgoCore", targets: ["YearAgoCore"]),
    ],
    targets: [
        .target(name: "YearAgoCore"),
        .testTarget(name: "YearAgoCoreTests", dependencies: ["YearAgoCore"]),
    ]
)
