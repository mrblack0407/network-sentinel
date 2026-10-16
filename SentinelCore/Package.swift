// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "SentinelCore",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "SentinelCore",
            targets: ["SentinelCore"]
        )
    ],
    targets: [
        .target(
            name: "SentinelCore"
        ),
        .testTarget(
            name: "SentinelCoreTests",
            dependencies: ["SentinelCore"]
        )
    ]
)
