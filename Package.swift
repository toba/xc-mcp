// swift-tools-version: 6.2

import PackageDescription

// Shared Swift settings for all targets
let sharedSwiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableExperimentalFeature("StrictConcurrency"),
]

let package = Package(
    name: "xc-mcp",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        // Monolithic server (all tools)
        .executable(name: "xc-mcp", targets: ["xc-mcp"]),

        // Focused servers for reduced token overhead
        .executable(name: "xc-project", targets: ["xc-project"]),
        .executable(name: "xc-simulator", targets: ["xc-simulator"]),
        .executable(name: "xc-device", targets: ["xc-device"]),
        .executable(name: "xc-debug", targets: ["xc-debug"]),
        .executable(name: "xc-swift", targets: ["xc-swift"]),
        .executable(name: "xc-build", targets: ["xc-build"]),
        .executable(name: "xc-strings", targets: ["xc-strings"]),

        // Shared library for utilities
        .library(name: "XCMCPCore", targets: ["XCMCPCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk", from: "0.9.0"),
        .package(url: "https://github.com/tuist/xcodeproj", from: "9.4.2"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.7.0"),
    ],
    targets: [
        // MARK: - Shared Core Library
        .target(
            name: "XCMCPCore",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk"),
            ],
            path: "Sources/Core",
            swiftSettings: sharedSwiftSettings
        ),

        // MARK: - Monolithic Server (all tools)
        .executableTarget(
            name: "xc-mcp",
            dependencies: [
                "XCMCPCore",
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "XcodeProj", package: "xcodeproj"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources",
            sources: [
                "CLI.swift",
                "Server/XcodeMCPServer.swift",
                "Tools",
                "Utilities",
            ],
            swiftSettings: sharedSwiftSettings
        ),

        // MARK: - Focused Servers

        // Project manipulation server (23 tools, ~5K tokens)
        // Stateless - uses XcodeProj for .xcodeproj file manipulation
        .executableTarget(
            name: "xc-project",
            dependencies: [
                "XCMCPCore",
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "XcodeProj", package: "xcodeproj"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/Servers/Project",
            swiftSettings: sharedSwiftSettings
        ),

        // Simulator management server (26 tools, ~6K tokens)
        // Includes simulator tools, UI automation, and simulator logging
        .executableTarget(
            name: "xc-simulator",
            dependencies: [
                "XCMCPCore",
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/Servers/Simulator",
            swiftSettings: sharedSwiftSettings
        ),

        // Physical device server (9 tools, ~2K tokens)
        // Device operations and device logging
        .executableTarget(
            name: "xc-device",
            dependencies: [
                "XCMCPCore",
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/Servers/Device",
            swiftSettings: sharedSwiftSettings
        ),

        // Debug server (8 tools, ~2K tokens)
        // LLDB debug sessions with persistent state
        .executableTarget(
            name: "xc-debug",
            dependencies: [
                "XCMCPCore",
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/Servers/Debug",
            swiftSettings: sharedSwiftSettings
        ),

        // Swift Package Manager server (6 tools, ~1.5K tokens)
        // SPM build, test, run operations
        .executableTarget(
            name: "xc-swift",
            dependencies: [
                "XCMCPCore",
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/Servers/Swift",
            swiftSettings: sharedSwiftSettings
        ),

        // Build orchestration server (12 tools, ~3K tokens)
        // macOS builds, discovery, and utility tools
        .executableTarget(
            name: "xc-build",
            dependencies: [
                "XCMCPCore",
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "XcodeProj", package: "xcodeproj"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/Servers/Build",
            swiftSettings: sharedSwiftSettings
        ),

        // XCStrings server (18 tools, ~6K tokens)
        // xcstrings file manipulation for localization management
        .executableTarget(
            name: "xc-strings",
            dependencies: [
                "XCMCPCore",
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/Servers/Strings",
            swiftSettings: sharedSwiftSettings
        ),

        // MARK: - Tests
        .testTarget(
            name: "xc-mcp-tests",
            dependencies: [
                "xc-mcp",
                "XCMCPCore",
            ],
            path: "Tests",
            swiftSettings: sharedSwiftSettings
        ),
    ]
)
