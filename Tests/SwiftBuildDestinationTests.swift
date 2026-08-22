import MCP
import Testing
import Foundation
@testable import XCMCPCore

/// The Apple SDKs that `xcrun` resolves on this machine.
///
/// The resolution tests spawn `xcrun`. A machine without the matching Xcode platform reports
/// nothing, so those tests skip rather than fail. Each check runs once.
private enum InstalledSDK {
    static let iPhoneSimulator = resolves("iphonesimulator")
    static let iPhoneOS = resolves("iphoneos")

    /// Returns true when `xcrun` reports a path for the named SDK.
    private static func resolves(_ name: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["--sdk", name, "--show-sdk-path"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}

/// Covers the `destination` argument that `swift_package_build` and `swift_package_test` accept.
///
/// The parsing and triple-shaping tests are pure. The resolution tests call `xcrun`, so they read
/// the SDKs the installed Xcode ships.
struct SwiftBuildDestinationTests {
    // MARK: - Parsing

    @Test
    func `Omitted destination parses as the host`() throws {
        let destination = try SwiftBuildDestination.parse(from: ["package_path": .string("/tmp/x")])
        #expect(destination == .macOS)
        #expect(destination.isHost)
    }

    @Test
    func `Named destination parses`() throws {
        #expect(
            try SwiftBuildDestination.parse(from: ["destination": .string("ios-simulator")])
                == .iOSSimulator,
        )
    }

    @Test
    func `Destination parsing ignores case`() throws {
        #expect(
            try SwiftBuildDestination.parse(from: ["destination": .string("iOS-Simulator")])
                == .iOSSimulator,
        )
    }

    @Test
    func `Unknown destination is rejected and the error lists the accepted values`() {
        #expect(throws: MCPError.self) {
            try SwiftBuildDestination.parse(from: ["destination": .string("android")])
        }

        do {
            _ = try SwiftBuildDestination.parse(from: ["destination": .string("android")])
            Issue.record("Expected an invalidParams error")
        } catch let error as MCPError {
            #expect("\(error)".contains("ios-simulator"))
        } catch {
            Issue.record("Expected an MCPError, got \(error)")
        }
    }

    // MARK: - Platform facts

    @Test
    func `Only the simulator destinations report as simulators`() {
        let simulators = SwiftBuildDestination.allCases.filter(\.isSimulator)
        #expect(
            simulators == [.iOSSimulator, .tvOSSimulator, .watchOSSimulator, .visionOSSimulator],
        )
    }

    @Test
    func `macos is the only host destination`() {
        #expect(SwiftBuildDestination.allCases.filter(\.isHost) == [.macOS])
    }

    @Test
    func `A simulator slice uses the host architecture`() {
        #expect(SwiftBuildDestination.iOSSimulator.architecture
            == SwiftBuildDestination.hostArchitecture)
    }

    @Test
    func `A device slice is 64-bit ARM and watchOS uses the ILP32 variant`() {
        #expect(SwiftBuildDestination.iOS.architecture == "arm64")
        #expect(SwiftBuildDestination.visionOS.architecture == "arm64")
        #expect(SwiftBuildDestination.watchOS.architecture == "arm64_32")
    }

    @Test
    func `visionOS uses the xros triple token and the xr SDK names`() {
        #expect(SwiftBuildDestination.visionOS.tripleOS == "xros")
        #expect(SwiftBuildDestination.visionOSSimulator.tripleOS == "xros")
        #expect(SwiftBuildDestination.visionOS.sdkName == "xros")
        #expect(SwiftBuildDestination.visionOSSimulator.sdkName == "xrsimulator")
    }

    @Test
    func `Every destination has a distinct SDK name`() {
        let names = Set(SwiftBuildDestination.allCases.map(\.sdkName))
        #expect(names.count == SwiftBuildDestination.allCases.count)
    }

    // MARK: - Flags and labels

    @Test
    func `The host labels itself as the host`() {
        #expect(SwiftBuildDestination.label(for: nil) == SwiftBuildDestination.hostLabel)
        #expect(SwiftBuildDestination.hostLabel.contains("macos"))
    }

    @Test
    func `A resolved destination emits the sdk and triple flags`() {
        let destination = ResolvedSwiftDestination(
            destination: .iOSSimulator,
            sdkPath: "/SDKs/iPhoneSimulator.sdk",
            triple: "arm64-apple-ios26.5-simulator",
        )
        #expect(destination.arguments == [
            "--sdk", "/SDKs/iPhoneSimulator.sdk",
            "--triple", "arm64-apple-ios26.5-simulator",
        ])
        #expect(destination.label == "ios-simulator destination arm64-apple-ios26.5-simulator")
        #expect(SwiftBuildDestination.label(for: destination) == destination.label)
    }

    // MARK: - Cold-cache flag

    @Test
    func `A non-host destination is cold even when the host cache is warm`() throws {
        // A populated `.build/checkouts` is what marks the host cache warm.
        let fm = FileManager.default
        let package = fm.temporaryDirectory.appendingPathComponent("warm-\(UUID().uuidString)")
        let checkouts = package.appendingPathComponent(".build/checkouts/dep")
        try fm.createDirectory(at: checkouts, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: package) }

        #expect(!SwiftRunner.isColdCache(packagePath: package.path, destination: .macOS))
        #expect(SwiftRunner.isColdCache(packagePath: package.path, destination: .iOSSimulator))
    }

    @Test
    func `A missing build directory is cold for the host`() {
        #expect(SwiftRunner.isColdCache(packagePath: "/nonexistent", destination: .macOS))
    }

    // MARK: - Timeout message

    @Test
    func `A host timeout message names the host and the cold cache`() {
        let message = SwiftRunner.timeoutMessage(
            command: "swift test",
            duration: .seconds(300),
            packagePath: "/pkg",
            destination: nil,
            usedColdCacheTimeout: true,
            advice: "Retry.",
        )
        #expect(message.hasPrefix("swift test timed out after"))
        #expect(message.contains("/pkg"))
        #expect(message.contains(SwiftBuildDestination.hostLabel))
        #expect(message.contains("Detected a cold SwiftPM cache"))
        #expect(message.hasSuffix("Retry."))
    }

    @Test
    func `A cross-compile timeout message names the cross-compile reason`() {
        let destination = ResolvedSwiftDestination(
            destination: .iOSSimulator,
            sdkPath: "/SDKs/iPhoneSimulator.sdk",
            triple: "arm64-apple-ios26.5-simulator",
        )
        let message = SwiftRunner.timeoutMessage(
            command: "swift build",
            duration: .seconds(900),
            packagePath: "/pkg",
            destination: destination,
            usedColdCacheTimeout: true,
            advice: "Retry.",
        )
        #expect(message.contains(destination.label))
        #expect(message.contains("A cross-compile builds the whole dependency graph again"))
        #expect(!message.contains("Detected a cold SwiftPM cache"))
    }

    @Test
    func `An explicit timeout drops the cold-cache sentence`() {
        let message = SwiftRunner.timeoutMessage(
            command: "swift build",
            duration: .seconds(60),
            packagePath: "/pkg",
            destination: nil,
            usedColdCacheTimeout: false,
            advice: "Retry.",
        )
        #expect(!message.contains("cold-cache timeout"))
        #expect(!message.contains("Detected a cold SwiftPM cache"))
    }

    // MARK: - Resolution

    @Test
    func `The host resolves to no destination`() async throws {
        let resolved = try await SwiftBuildDestination.macOS.resolve()
        #expect(resolved == nil)
    }

    @Test(.enabled(if: InstalledSDK.iPhoneSimulator))
    func `The iOS simulator resolves to a simulator SDK and triple`() async throws {
        let resolved = try #require(try await SwiftBuildDestination.iOSSimulator.resolve())
        #expect(resolved.sdkPath.contains("iPhoneSimulator"))
        #expect(FileManager.default.fileExists(atPath: resolved.sdkPath))
        #expect(resolved.triple.hasSuffix("-simulator"))
        #expect(resolved.triple.contains("-apple-ios"))
        #expect(resolved.triple.hasPrefix(SwiftBuildDestination.hostArchitecture))
    }

    @Test(.enabled(if: InstalledSDK.iPhoneOS))
    func `The iOS device resolves to a device SDK and an unsuffixed triple`() async throws {
        let resolved = try #require(try await SwiftBuildDestination.iOS.resolve())
        #expect(resolved.sdkPath.contains("iPhoneOS"))
        #expect(!resolved.triple.hasSuffix("-simulator"))
        #expect(resolved.triple.hasPrefix("arm64-apple-ios"))
    }
}
