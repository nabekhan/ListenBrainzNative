// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ListenBrainzKit",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .visionOS(.v1),
        .watchOS(.v9),
    ],
    products: [
        .library(
            name: "ListenBrainzKit",
            targets: ["ListenBrainzKit"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "ListenBrainzKit",
            dependencies: [],
            path: "Sources"
        ),
        .testTarget(
            name: "ListenBrainzKitTests",
            dependencies: ["ListenBrainzKit"]
        ),
    ]
)
