import Foundation
import MCP
import Synchronization

/// Wrapper for executing xcodebuild commands.
///
/// `XcodebuildRunner` provides a Swift interface for invoking Xcode's command-line
/// build tool. It supports building, testing, cleaning, and querying project information.
///
/// ## Example
///
/// ```swift
/// let runner = XcodebuildRunner()
///
/// // Build for simulator
/// let result = try await runner.build(
///     projectPath: "MyApp.xcodeproj",
///     scheme: "MyApp",
///     destination: "platform=iOS Simulator,name=iPhone 15",
///     configuration: "Debug"
/// )
///
/// if result.succeeded {
///     print("Build succeeded")
/// }
/// ```
public struct XcodebuildRunner: Sendable {
    /// Default timeout for build operations (5 minutes)
    public static let defaultTimeout: TimeInterval = 300

    /// Timeout for no-output detection (30 seconds without output = stuck)
    public static let outputTimeout: Duration = .seconds(30)

    /// Creates a new xcodebuild runner.
    public init() {}

    /// Executes an xcodebuild command with the given arguments.
    ///
    /// - Parameter arguments: The command-line arguments to pass to xcodebuild.
    /// - Returns: The result containing exit code and output.
    /// - Throws: An error if the process fails to launch.
    public func run(arguments: [String]) async throws -> XcodebuildResult {
        try await run(arguments: arguments, timeout: Self.defaultTimeout, onProgress: nil)
    }

    /// Executes an xcodebuild command with timeout and optional progress callback.
    ///
    /// - Parameters:
    ///   - arguments: The command-line arguments to pass to xcodebuild.
    ///   - timeout: Maximum time to wait for the build to complete.
    ///   - onProgress: Optional callback invoked with output lines as they arrive.
    /// - Returns: The result containing exit code and output.
    /// - Throws: An error if the process fails to launch or times out.
    public func run(
        arguments: [String],
        timeout: TimeInterval,
        onProgress: (@Sendable (String) -> Void)?
    ) async throws -> XcodebuildResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["xcodebuild"] + arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Collected output
        let outputActor = OutputCollector()

        // Track last output time for stuck detection
        let lastOutputTime = LastOutputTime()

        // Set up async reading of stdout
        let stdoutHandle = stdoutPipe.fileHandleForReading
        stdoutHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                outputActor.appendStdout(data)
                lastOutputTime.update()
                if let text = String(data: data, encoding: .utf8) {
                    onProgress?(text)
                }
            }
        }

        // Set up async reading of stderr
        let stderrHandle = stderrPipe.fileHandleForReading
        stderrHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                outputActor.appendStderr(data)
                lastOutputTime.update()
                if let text = String(data: data, encoding: .utf8) {
                    onProgress?(text)
                }
            }
        }

        try process.run()

        // Wait for process with timeout
        let startTime = ContinuousClock.now

        while process.isRunning {
            // Check total timeout
            if startTime.duration(to: .now) > .seconds(timeout) {
                process.terminate()
                let (stdout, stderr) = outputActor.getOutput()
                throw XcodebuildError.timeout(
                    duration: timeout,
                    partialOutput: stdout + stderr
                )
            }

            // Check for stuck process (no output for too long)
            let timeSinceLastOutput = lastOutputTime.timeSinceLastOutput()
            if timeSinceLastOutput > Self.outputTimeout {
                process.terminate()
                let (stdout, stderr) = outputActor.getOutput()
                let seconds =
                    Double(timeSinceLastOutput.components.seconds)
                    + Double(timeSinceLastOutput.components.attoseconds) / 1e18
                throw XcodebuildError.stuckProcess(
                    noOutputFor: seconds,
                    partialOutput: stdout + stderr
                )
            }

            try await Task.sleep(nanoseconds: 100_000_000)  // 100ms
        }

        // Clean up handlers
        stdoutHandle.readabilityHandler = nil
        stderrHandle.readabilityHandler = nil

        // Read any remaining data
        let remainingStdout = stdoutHandle.readDataToEndOfFile()
        let remainingStderr = stderrHandle.readDataToEndOfFile()

        if !remainingStdout.isEmpty {
            outputActor.appendStdout(remainingStdout)
        }
        if !remainingStderr.isEmpty {
            outputActor.appendStderr(remainingStderr)
        }

        let (stdout, stderr) = outputActor.getOutput()

        return XcodebuildResult(
            exitCode: process.terminationStatus,
            stdout: stdout,
            stderr: stderr
        )
    }

    /// Builds a project for a specific destination.
    ///
    /// - Parameters:
    ///   - projectPath: Path to the .xcodeproj file (mutually exclusive with workspacePath).
    ///   - workspacePath: Path to the .xcworkspace file (mutually exclusive with projectPath).
    ///   - scheme: The scheme to build.
    ///   - destination: The build destination (e.g., "platform=iOS Simulator,id=<UDID>").
    ///   - configuration: Build configuration (Debug or Release). Defaults to Debug.
    ///   - additionalArguments: Extra arguments to pass to xcodebuild.
    /// - Returns: The build result containing exit code and output.
    /// - Throws: An error if the process fails to launch.
    public func build(
        projectPath: String? = nil,
        workspacePath: String? = nil,
        scheme: String,
        destination: String,
        configuration: String = "Debug",
        additionalArguments: [String] = [],
        timeout: TimeInterval = defaultTimeout,
        onProgress: (@Sendable (String) -> Void)? = nil
    ) async throws -> XcodebuildResult {
        var args: [String] = []

        if let workspacePath {
            args += ["-workspace", workspacePath]
        } else if let projectPath {
            args += ["-project", projectPath]
        }

        args += [
            "-scheme", scheme,
            "-destination", destination,
            "-configuration", configuration,
            "build",
        ]

        args += additionalArguments

        return try await run(arguments: args, timeout: timeout, onProgress: onProgress)
    }

    /// Builds a single target for a specific destination.
    ///
    /// Unlike ``build(projectPath:workspacePath:scheme:destination:configuration:additionalArguments:timeout:onProgress:)``
    /// which builds an entire scheme, this method uses `-target` to compile a single target.
    /// This is useful for fast type-checking of auxiliary targets (e.g. test support modules)
    /// without building the full dependency graph of a scheme.
    ///
    /// - Parameters:
    ///   - projectPath: Path to the .xcodeproj file (mutually exclusive with workspacePath).
    ///   - workspacePath: Path to the .xcworkspace file (mutually exclusive with projectPath).
    ///   - target: The target to build.
    ///   - destination: The build destination (e.g., "platform=macOS").
    ///   - configuration: Build configuration (Debug or Release). Defaults to Debug.
    ///   - additionalArguments: Extra arguments to pass to xcodebuild.
    ///   - timeout: Maximum time to wait for the build to complete.
    ///   - onProgress: Optional callback invoked with output lines as they arrive.
    /// - Returns: The build result containing exit code and output.
    /// - Throws: An error if the process fails to launch.
    public func buildTarget(
        projectPath: String? = nil,
        workspacePath: String? = nil,
        target: String,
        destination: String,
        configuration: String = "Debug",
        additionalArguments: [String] = [],
        timeout: TimeInterval = defaultTimeout,
        onProgress: (@Sendable (String) -> Void)? = nil
    ) async throws -> XcodebuildResult {
        var args: [String] = []

        if let workspacePath {
            args += ["-workspace", workspacePath]
        } else if let projectPath {
            args += ["-project", projectPath]
        }

        args += [
            "-target", target,
            "-destination", destination,
            "-configuration", configuration,
            "build",
        ]

        args += additionalArguments

        return try await run(arguments: args, timeout: timeout, onProgress: onProgress)
    }

    /// Builds and runs tests for a scheme.
    ///
    /// - Parameters:
    ///   - projectPath: Path to the .xcodeproj file (mutually exclusive with workspacePath).
    ///   - workspacePath: Path to the .xcworkspace file (mutually exclusive with projectPath).
    ///   - scheme: The scheme containing tests to run.
    ///   - destination: The test destination (e.g., "platform=iOS Simulator,id=<UDID>").
    ///   - configuration: Build configuration (Debug or Release). Defaults to Debug.
    ///   - onlyTesting: Test identifiers to run exclusively (e.g., "MyTests/testFoo").
    ///   - skipTesting: Test identifiers to skip.
    ///   - enableCodeCoverage: Whether to enable code coverage collection.
    ///   - resultBundlePath: Path to store the .xcresult bundle.
    ///   - additionalArguments: Extra arguments to pass to xcodebuild.
    /// - Returns: The test result containing exit code and output.
    /// - Throws: An error if the process fails to launch.
    public func test(
        projectPath: String? = nil,
        workspacePath: String? = nil,
        scheme: String,
        destination: String,
        configuration: String = "Debug",
        onlyTesting: [String]? = nil,
        skipTesting: [String]? = nil,
        enableCodeCoverage: Bool = false,
        resultBundlePath: String? = nil,
        additionalArguments: [String] = [],
        timeout: TimeInterval = defaultTimeout
    ) async throws -> XcodebuildResult {
        var args: [String] = []

        if let workspacePath {
            args += ["-workspace", workspacePath]
        } else if let projectPath {
            args += ["-project", projectPath]
        }

        args += [
            "-scheme", scheme,
            "-destination", destination,
            "-configuration", configuration,
        ]

        // Add test selection arguments
        if let onlyTesting {
            for testIdentifier in onlyTesting {
                args += ["-only-testing:\(testIdentifier)"]
            }
        }

        if let skipTesting {
            for testIdentifier in skipTesting {
                args += ["-skip-testing:\(testIdentifier)"]
            }
        }

        // Add code coverage arguments
        if enableCodeCoverage {
            args += ["-enableCodeCoverage", "YES"]
        }

        if let resultBundlePath {
            args += ["-resultBundlePath", resultBundlePath]
        }

        args += ["test"]
        args += additionalArguments

        return try await run(arguments: args, timeout: timeout, onProgress: nil)
    }

    /// Cleans build artifacts for a scheme.
    ///
    /// - Parameters:
    ///   - projectPath: Path to the .xcodeproj file (mutually exclusive with workspacePath).
    ///   - workspacePath: Path to the .xcworkspace file (mutually exclusive with projectPath).
    ///   - scheme: The scheme to clean.
    ///   - configuration: Build configuration (Debug or Release). Defaults to Debug.
    /// - Returns: The clean result containing exit code and output.
    /// - Throws: An error if the process fails to launch.
    public func clean(
        projectPath: String? = nil,
        workspacePath: String? = nil,
        scheme: String,
        configuration: String = "Debug"
    ) async throws -> XcodebuildResult {
        var args: [String] = []

        if let workspacePath {
            args += ["-workspace", workspacePath]
        } else if let projectPath {
            args += ["-project", projectPath]
        }

        args += ["-scheme", scheme, "-configuration", configuration, "clean"]

        return try await run(arguments: args)
    }

    /// Lists all schemes in a project or workspace.
    ///
    /// - Parameters:
    ///   - projectPath: Path to the .xcodeproj file (mutually exclusive with workspacePath).
    ///   - workspacePath: Path to the .xcworkspace file (mutually exclusive with projectPath).
    /// - Returns: The result containing JSON-formatted scheme list.
    /// - Throws: An error if the process fails to launch.
    public func listSchemes(
        projectPath: String? = nil,
        workspacePath: String? = nil
    ) async throws -> XcodebuildResult {
        var args: [String] = ["-list", "-json"]

        if let workspacePath {
            args += ["-workspace", workspacePath]
        } else if let projectPath {
            args += ["-project", projectPath]
        }

        return try await run(arguments: args)
    }

    /// Shows build settings for a scheme.
    ///
    /// - Parameters:
    ///   - projectPath: Path to the .xcodeproj file (mutually exclusive with workspacePath).
    ///   - workspacePath: Path to the .xcworkspace file (mutually exclusive with projectPath).
    ///   - scheme: The scheme to query.
    ///   - configuration: Build configuration (Debug or Release). Defaults to Debug.
    /// - Returns: The result containing JSON-formatted build settings.
    /// - Throws: An error if the process fails to launch.
    public func showBuildSettings(
        projectPath: String? = nil,
        workspacePath: String? = nil,
        scheme: String,
        configuration: String = "Debug",
        destination: String? = nil
    ) async throws -> XcodebuildResult {
        var args: [String] = []

        if let workspacePath {
            args += ["-workspace", workspacePath]
        } else if let projectPath {
            args += ["-project", projectPath]
        }

        args += [
            "-scheme", scheme,
            "-configuration", configuration,
        ]

        if let destination {
            args += ["-destination", destination]
        }

        args += [
            "-showBuildSettings",
            "-json",
        ]

        return try await run(arguments: args)
    }
}

// MARK: - Helper Types

/// Errors specific to xcodebuild execution.
public enum XcodebuildError: LocalizedError, Sendable, MCPErrorConvertible {
    /// The build exceeded the maximum allowed time.
    case timeout(duration: TimeInterval, partialOutput: String)

    /// The build process stopped producing output (likely stuck).
    case stuckProcess(noOutputFor: TimeInterval, partialOutput: String)

    public var errorDescription: String? {
        switch self {
        case let .timeout(duration, _):
            return "Build timed out after \(Int(duration)) seconds"
        case let .stuckProcess(noOutputFor, _):
            return "Build appears stuck (no output for \(Int(noOutputFor)) seconds)"
        }
    }

    /// The partial output captured before the error occurred.
    public var partialOutput: String {
        switch self {
        case let .timeout(_, output), let .stuckProcess(_, output):
            return output
        }
    }

    public func toMCPError() -> MCPError {
        let errors = ErrorExtractor.extractBuildErrors(from: partialOutput)
        let detail = errors.isEmpty ? partialOutput.suffix(2000) : errors[...]
        return MCPError.internalError("\(errorDescription ?? "Build error")\n\n\(detail)")
    }
}

/// Thread-safe output collector that appends Data synchronously from readabilityHandler
/// callbacks (which run on a serial dispatch queue), avoiding Task reordering issues.
private final class OutputCollector: Sendable {
    private let stdoutData = Mutex(Data())
    private let stderrData = Mutex(Data())

    func appendStdout(_ data: Data) {
        stdoutData.withLock { $0.append(data) }
    }

    func appendStderr(_ data: Data) {
        stderrData.withLock { $0.append(data) }
    }

    func getOutput() -> (stdout: String, stderr: String) {
        let out = stdoutData.withLock { String(data: $0, encoding: .utf8) ?? "" }
        let err = stderrData.withLock { String(data: $0, encoding: .utf8) ?? "" }
        return (out, err)
    }
}

/// Thread-safe tracker for the last time output was received.
private final class LastOutputTime: Sendable {
    private let lastTime = Mutex(ContinuousClock.now)

    func update() {
        lastTime.withLock { $0 = .now }
    }

    func timeSinceLastOutput() -> Duration {
        lastTime.withLock { $0.duration(to: .now) }
    }
}
