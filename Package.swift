// swift-tools-version: 6.3

import PackageDescription

/// Shared Swift settings for all targets
let sharedSwiftSettings: [SwiftSetting] = [
  .swiftLanguageMode(.v6)
]

let package = Package(
  name: "xc-mcp",
  platforms: [
    .macOS(.v26)
  ],
  products: [
    // Single multicall binary — symlinks (xc-build, xc-debug, etc.) select the focused server
    .executable(name: "xc-mcp", targets: ["xc-mcp"]),

    // Shared libraries
    .library(name: "XCMCPCore", targets: ["XCMCPCore"]),
    .library(name: "XCMCPTools", targets: ["XCMCPTools"]),
  ],
  dependencies: [
    .package(url: "https://github.com/modelcontextprotocol/swift-sdk", from: "0.12.0"),
    .package(url: "https://github.com/tuist/xcodeproj", from: "9.10.1"),
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.7.1"),
    .package(url: "https://github.com/swiftlang/swift-subprocess", from: "0.4.0"),
    .package(url: "https://github.com/toba/swiftiomatic-plugins", from: "0.32.2"),
  ],
  targets: [
    // MARK: - Shared Core Library

    .target(
      name: "XCMCPCore",
      dependencies: [
        .product(name: "MCP", package: "swift-sdk"),
        .product(name: "Subprocess", package: "swift-subprocess"),
      ],
      path: "Sources/Core",
      swiftSettings: sharedSwiftSettings,
      plugins: [
        .plugin(name: "SwiftiomaticBuildToolPlugin", package: "swiftiomatic-plugins"),
      ],
    ),

    // MARK: - Shared Tools Library

    .target(
      name: "XCMCPTools",
      dependencies: [
        "XCMCPCore",
        .product(name: "MCP", package: "swift-sdk"),
        .product(name: "Subprocess", package: "swift-subprocess"),
        .product(name: "XcodeProj", package: "xcodeproj"),
      ],
      path: "Sources/Tools",
      swiftSettings: sharedSwiftSettings,
      plugins: [
        .plugin(name: "SwiftiomaticBuildToolPlugin", package: "swiftiomatic-plugins"),
      ],
    ),

    // MARK: - Monolithic Server (all tools)

    // Single multicall binary — argv[0] selects the focused server variant.
    // Symlinks (xc-build, xc-debug, etc.) are created at install time.
    .executableTarget(
      name: "xc-mcp",
      dependencies: [
        "XCMCPCore",
        "XCMCPTools",
        .product(name: "MCP", package: "swift-sdk"),
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      path: "Sources",
      sources: [
        "CLI.swift",
        "Server/MonolithicCLI.swift",
        "Server/XcodeMCPServer.swift",
        "Servers/Build/BuildCLI.swift",
        "Servers/Build/BuildMCPServer.swift",
        "Servers/Debug/DebugCLI.swift",
        "Servers/Debug/DebugMCPServer.swift",
        "Servers/Device/DeviceCLI.swift",
        "Servers/Device/DeviceMCPServer.swift",
        "Servers/Project/ProjectCLI.swift",
        "Servers/Project/ProjectMCPServer.swift",
        "Servers/Simulator/SimulatorCLI.swift",
        "Servers/Simulator/SimulatorMCPServer.swift",
        "Servers/Strings/StringsCLI.swift",
        "Servers/Strings/StringsMCPServer.swift",
        "Servers/Swift/SwiftCLI.swift",
        "Servers/Swift/SwiftMCPServer.swift",
      ],
      swiftSettings: sharedSwiftSettings,
      plugins: [
        .plugin(name: "SwiftiomaticBuildToolPlugin", package: "swiftiomatic-plugins"),
      ],
    ),

    // MARK: - Tests

    .testTarget(
      name: "xc-mcp-tests",
      dependencies: [
        "XCMCPCore",
        "XCMCPTools",
      ],
      path: "Tests",
      resources: [
        .copy("Fixtures")
      ],
      swiftSettings: sharedSwiftSettings,
    ),
  ],
)
