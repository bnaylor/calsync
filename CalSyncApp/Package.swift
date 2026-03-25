// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "CalSyncApp",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        // No external dependencies needed for the app itself beyond what is in CalSyncLib
    ],
    targets: [
        .target(
            name: "CalSyncLib",
            path: "Sources/CalSyncLib"
        ),
        .executableTarget(
            name: "CalSyncApp",
            dependencies: ["CalSyncLib"],
            path: "Sources/CalSyncApp",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ]
)
