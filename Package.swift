// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "StreamKit",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "StreamKit",
            targets: ["StreamKit"]
        )
    ],
    targets: [
        .target(
            name: "StreamKit",
            sources: ["PlaybackCore", "PublicAPI", "InternalSupport"],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency")
            ]
        ),
        .testTarget(
            name: "StreamKitTests",
            dependencies: ["StreamKit"],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency")
            ]
        )
    ]
)
