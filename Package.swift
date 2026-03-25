// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CalSync",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "CalSyncLib",
            dependencies: []
        ),
        .executableTarget(
            name: "CalSync",
            dependencies: [
                "CalSyncLib",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "CalSyncTests",
            dependencies: ["CalSyncLib"]
        ),
    ]
)
