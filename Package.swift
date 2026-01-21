// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "xcode-mcp",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(
            name: "xcode-mcp-server",
            targets: ["xcode-mcp-server"]
        ),
        .library(
            name: "XcodeMCP",
            targets: ["XcodeMCP"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk", from: "0.9.0"),
        .package(url: "https://github.com/tuist/xcodeproj", from: "9.4.2"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.7.0"),
    ],
    targets: [
        .target(
            name: "XcodeMCP",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "XcodeProj", package: "xcodeproj"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .executableTarget(
            name: "xcode-mcp-server",
            dependencies: [
                "XcodeMCP",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "XcodeMCPTests",
            dependencies: [
                "XcodeMCP"
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
    ]
)
