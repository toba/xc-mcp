import Foundation

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
    public static let outputTimeout: TimeInterval = 30

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
                Task {
                    await lastOutputTime.update()
                    if let line = String(data: data, encoding: .utf8) {
                        await outputActor.appendStdout(line)
                        onProgress?(line)
                    }
                }
            }
        }

        // Set up async reading of stderr
        let stderrHandle = stderrPipe.fileHandleForReading
        stderrHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                Task {
                    await lastOutputTime.update()
                    if let line = String(data: data, encoding: .utf8) {
                        await outputActor.appendStderr(line)
                        onProgress?(line)
                    }
                }
            }
        }

        try process.run()

        // Wait for process with timeout
        let startTime = Date()

        while process.isRunning {
            // Check total timeout
            if Date().timeIntervalSince(startTime) > timeout {
                process.terminate()
                let (stdout, stderr) = await outputActor.getOutput()
                throw XcodebuildError.timeout(
                    duration: timeout,
                    partialOutput: stdout + stderr
                )
            }

            // Check for stuck process (no output for too long)
            let timeSinceLastOutput = await lastOutputTime.timeSinceLastOutput()
            if timeSinceLastOutput > Self.outputTimeout {
                process.terminate()
                let (stdout, stderr) = await outputActor.getOutput()
                throw XcodebuildError.stuckProcess(
                    noOutputFor: timeSinceLastOutput,
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

        if !remainingStdout.isEmpty, let line = String(data: remainingStdout, encoding: .utf8) {
            await outputActor.appendStdout(line)
        }
        if !remainingStderr.isEmpty, let line = String(data: remainingStderr, encoding: .utf8) {
            await outputActor.appendStderr(line)
        }

        let (stdout, stderr) = await outputActor.getOutput()

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
        additionalArguments: [String] = []
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

        return try await run(arguments: args)
    }

    /// Builds and runs tests for a scheme.
    ///
    /// - Parameters:
    ///   - projectPath: Path to the .xcodeproj file (mutually exclusive with workspacePath).
    ///   - workspacePath: Path to the .xcworkspace file (mutually exclusive with projectPath).
    ///   - scheme: The scheme containing tests to run.
    ///   - destination: The test destination (e.g., "platform=iOS Simulator,id=<UDID>").
    ///   - configuration: Build configuration (Debug or Release). Defaults to Debug.
    ///   - additionalArguments: Extra arguments to pass to xcodebuild.
    /// - Returns: The test result containing exit code and output.
    /// - Throws: An error if the process fails to launch.
    public func test(
        projectPath: String? = nil,
        workspacePath: String? = nil,
        scheme: String,
        destination: String,
        configuration: String = "Debug",
        additionalArguments: [String] = []
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
            "test",
        ]

        args += additionalArguments

        return try await run(arguments: args)
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
        configuration: String = "Debug"
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
            "-showBuildSettings",
            "-json",
        ]

        return try await run(arguments: args)
    }
}

// MARK: - Helper Types

/// Errors specific to xcodebuild execution.
public enum XcodebuildError: LocalizedError {
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
}

/// Actor for safely collecting output from multiple sources.
private actor OutputCollector {
    private var stdout = ""
    private var stderr = ""

    func appendStdout(_ text: String) {
        stdout += text
    }

    func appendStderr(_ text: String) {
        stderr += text
    }

    func getOutput() -> (stdout: String, stderr: String) {
        return (stdout, stderr)
    }
}

/// Actor for tracking the last time output was received.
private actor LastOutputTime {
    private var lastTime = Date()

    func update() {
        lastTime = Date()
    }

    func timeSinceLastOutput() -> TimeInterval {
        return Date().timeIntervalSince(lastTime)
    }
}
