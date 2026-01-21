// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "xc-mcp",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(
            name: "xc-mcp",
            targets: ["xc-mcp"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk", from: "0.9.0"),
        .package(url: "https://github.com/tuist/xcodeproj", from: "9.4.2"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.7.0"),
    ],
    targets: [
        .executableTarget(
            name: "xc-mcp",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "XcodeProj", package: "xcodeproj"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "xc-mcp-tests",
            dependencies: [
                "xc-mcp"
            ],
            path: "Tests",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
    ]
)
