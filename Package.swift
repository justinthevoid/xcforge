// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "xcforge",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.11.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "xcforgeCore",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "Logging", package: "swift-log"),
            ],
            linkerSettings: [
                .linkedFramework("ScreenCaptureKit"),
            ]
        ),
        .executableTarget(
            name: "xcforge",
            dependencies: [
                "xcforgeCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .testTarget(
            name: "xcforgeTests",
            dependencies: [
                "xcforgeCore",
                "xcforge",
            ]
        ),
    ]
)
