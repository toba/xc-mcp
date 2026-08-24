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
    .package(url: "https://github.com/tuist/xcodeproj", from: "9.15.1"),
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.7.1"),
    .package(url: "https://github.com/swiftlang/swift-subprocess", from: "0.4.0"),
    .package(url: "https://github.com/toba/swiftiomatic-plugins", from: "3.0.0"),

    // 1.11.1 is the floor because it is the first release that ships the library dynamic under the
    // name TobaCoreLibrary. A static product is absorbed into every image that links it, so two
    // images in one process hold two type descriptors for each TobaCore type, and a conformance
    // lookup that compares them returns a null metadata the Swift runtime dies on. The floor was
    // 1.5.0, the first release with `Data.hexString(uppercase:)`. `ShortHash` needs the lower-case
    // form, and the property alone returns upper case.
    .package(url: "https://github.com/toba/toba-core", from: "1.11.1"),
    // 1.0.3 is the floor because it is the first release that ships the library dynamic under the
    // name TobaConcurrencyLibrary. A static product is absorbed into every image that links it, and
    // two type descriptors for one type make a conformance lookup return a null metadata the Swift
    // runtime dies on. The floor was 1.0.0, where `Mutex+support` ships unchanged.
    .package(url: "https://github.com/toba/toba-concurrency", from: "1.0.3"),
    // 1.0.3 is the floor because it is the release where `ByteExpressible` and `StableHasher`
    // took their current shape. Earlier releases spell the `String` conformance differently.
    .package(url: "https://github.com/toba/toba-hash", from: "1.0.3"),
    // 1.0.0 is the floor for the API this package calls. 1.3.0 is the floor in practice because it
    // is the first release that reads `PlatformImage` from `TobaCore` instead of `TobaUI`. An
    // earlier release pulls a whole UI chain into the test target.
    .package(url: "https://github.com/toba/toba-testing", from: "1.3.0"),
  ],
  targets: [
    // MARK: - Shared Core Library

    .target(
      name: "XCMCPCore",
      dependencies: [
        .product(name: "MCP", package: "swift-sdk"),
        .product(name: "Subprocess", package: "swift-subprocess"),
        .product(name: "TobaConcurrencyLibrary", package: "toba-concurrency"),
        .product(name: "TobaCoreLibrary", package: "toba-core"),
        .product(name: "TobaHash", package: "toba-hash"),
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
        .product(name: "TobaCoreLibrary", package: "toba-core"),
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
        .product(name: "TobaTesting", package: "toba-testing"),
      ],
      path: "Tests",
      // `TestFixtures` reads `Tests/TestData` straight from the source tree, so the fixtures need
      // no resource rule and no bundle lookup.
      exclude: ["TestData"],
      swiftSettings: sharedSwiftSettings,
    ),
  ],
)
