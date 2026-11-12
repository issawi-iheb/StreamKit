// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "StreamKit",
    platforms: [
        .iOS(.v18)
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
            sources: ["PublicAPI", "Internal"],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency")
            ]
        ),
        .testTarget(
            name: "StreamKitTests",
            dependencies: ["StreamKit"],
            sources: [
                "Advertising",
                "Diagnostics",
                "Media",
                "Playback",
                "Presentation",
                "Support"
            ],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency")
            ]
        )
    ]
)
