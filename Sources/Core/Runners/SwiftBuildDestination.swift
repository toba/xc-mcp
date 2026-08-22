import MCP
import Foundation
import Subprocess

/// A cross-compilation target for `swift build` and `swift test`.
///
/// SwiftPM compiles for the host platform by default. A package that keeps its iOS sources behind
/// `#if canImport(UIKit)` therefore never gets compiled on macOS, and a compile error in that code
/// stays hidden. A destination supplies the two SwiftPM flags that point the compiler at another
/// Apple SDK: `--sdk` with the SDK path and `--triple` with the target triple.
///
/// A simulator destination needs no booted simulator. The SDK comes from the installed Xcode, and
/// nothing launches a device.
public enum SwiftBuildDestination: String, Sendable, CaseIterable {
    /// The host platform. Adds no flags, which is the SwiftPM default.
    case macOS = "macos"
    case iOSSimulator = "ios-simulator"
    case iOS = "ios"
    case tvOSSimulator = "tvos-simulator"
    case tvOS = "tvos"
    case watchOSSimulator = "watchos-simulator"
    case watchOS = "watchos"
    case visionOSSimulator = "visionos-simulator"
    case visionOS = "visionos"

    /// The accepted `destination` values, in schema order.
    public static let acceptedValues: [String] = allCases.map(\.rawValue)

    /// The label a tool result prints when it builds for the host.
    public static var hostLabel: String { "\(macOS.rawValue) destination (host)" }

    /// The label a tool result prints for a resolved destination.
    ///
    /// - Parameter destination: The resolved destination, or `nil` for the host.
    public static func label(for destination: ResolvedSwiftDestination?) -> String {
        destination?.label ?? hostLabel
    }

    /// Whether this destination is the host platform, which needs no extra flags.
    public var isHost: Bool { self == .macOS }

    /// Whether this destination is a simulator rather than a physical device.
    public var isSimulator: Bool {
        switch self {
            case .iOSSimulator, .tvOSSimulator, .watchOSSimulator, .visionOSSimulator: true
            case .macOS, .iOS, .tvOS, .watchOS, .visionOS: false
        }
    }

    /// The `xcrun --sdk` name for this destination.
    public var sdkName: String {
        switch self {
            case .macOS: "macosx"
            case .iOSSimulator: "iphonesimulator"
            case .iOS: "iphoneos"
            case .tvOSSimulator: "appletvsimulator"
            case .tvOS: "appletvos"
            case .watchOSSimulator: "watchsimulator"
            case .watchOS: "watchos"
            case .visionOSSimulator: "xrsimulator"
            case .visionOS: "xros"
        }
    }

    /// The operating-system component of the target triple. visionOS uses the token `xros`.
    public var tripleOS: String {
        switch self {
            case .macOS: "macosx"
            case .iOSSimulator, .iOS: "ios"
            case .tvOSSimulator, .tvOS: "tvos"
            case .watchOSSimulator, .watchOS: "watchos"
            case .visionOSSimulator, .visionOS: "xros"
        }
    }

    /// The architecture component of the target triple.
    ///
    /// A simulator slice matches the host architecture, because the simulator runs native code. A
    /// device slice is always 64-bit ARM. watchOS devices use the `arm64_32` ILP32 variant.
    public var architecture: String {
        if isSimulator || self == .macOS { return Self.hostArchitecture }
        return self == .watchOS ? "arm64_32" : "arm64"
    }

    /// The architecture of the machine running the server.
    public static var hostArchitecture: String {
        #if arch(arm64)
            "arm64"
        #else
            "x86_64"
        #endif
    }

    /// Parses the `destination` tool argument.
    ///
    /// - Parameter arguments: The tool call arguments.
    /// - Returns: The named destination, or ``macOS`` when the caller omits the argument.
    /// - Throws: ``MCPError/invalidParams(_:)`` when the value names no known destination.
    public static func parse(
        from arguments: [String: Value],
    ) throws(MCPError) -> SwiftBuildDestination {
        guard let raw = arguments.getString("destination") else { return .macOS }
        let normalized = raw.lowercased()
        guard let destination = SwiftBuildDestination(rawValue: normalized) else {
            throw .invalidParams(
                "Unknown destination '\(raw)'. Accepted values: \(acceptedValues.joined(separator: ", ")).",
            )
        }
        return destination
    }

    /// Resolves the SDK path and target triple for this destination.
    ///
    /// - Returns: The resolved destination, or `nil` for the host, which needs no flags.
    /// - Throws: ``MCPError/internalError(_:)`` when `xcrun` cannot report the SDK.
    public func resolve() async throws -> ResolvedSwiftDestination? {
        guard !isHost else { return nil }
        // The two lookups share no input and no result, so they run together.
        async let pathLookup = Self.xcrunSDK(sdkName, query: "--show-sdk-path")
        async let versionLookup = Self.xcrunSDK(sdkName, query: "--show-sdk-version")
        let (sdkPath, sdkVersion) = try await (pathLookup, versionLookup)
        var triple = "\(architecture)-apple-\(tripleOS)\(sdkVersion)"
        if isSimulator { triple += "-simulator" }
        return ResolvedSwiftDestination(destination: self, sdkPath: sdkPath, triple: triple)
    }

    /// Runs one `xcrun --sdk <name> <query>` lookup and returns its trimmed stdout.
    private static func xcrunSDK(_ sdkName: String, query: String) async throws -> String {
        let result = try await ProcessResult.runSubprocess(
            .name("xcrun"),
            arguments: Arguments(["--sdk", sdkName, query]),
            timeout: .seconds(60),
        )
        let value = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.succeeded, !value.isEmpty else {
            throw MCPError.internalError(
                "xcrun could not resolve the \(sdkName) SDK (\(query)). Install the matching Xcode platform, then retry. \(result.errorOutput.trimmingCharacters(in: .whitespacesAndNewlines))",
            )
        }
        return value
    }
}

/// A ``SwiftBuildDestination`` resolved to a concrete SDK path and target triple.
public struct ResolvedSwiftDestination: Sendable {
    /// The destination the caller named.
    public let destination: SwiftBuildDestination

    /// The absolute path of the SDK that `xcrun` reported.
    public let sdkPath: String

    /// The target triple, such as `arm64-apple-ios26.5-simulator`.
    public let triple: String

    public init(destination: SwiftBuildDestination, sdkPath: String, triple: String) {
        self.destination = destination
        self.sdkPath = sdkPath
        self.triple = triple
    }

    /// The SwiftPM flags that select this destination.
    public var arguments: [String] { ["--sdk", sdkPath, "--triple", triple] }

    /// A label for a tool result, such as `ios-simulator destination arm64-apple-ios26.5-simulator`.
    public var label: String { "\(destination.rawValue) destination \(triple)" }
}
