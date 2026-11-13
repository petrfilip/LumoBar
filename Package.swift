// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "LumoBar",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "LumoBar", targets: ["LumoBar"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "LumoBar",
            dependencies: ["Sparkle"],
            path: "Sources/LumoBar",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "LumoBarTests",
            dependencies: ["LumoBar"],
            path: "Tests/LumoBarTests"
        )
    ]
)
