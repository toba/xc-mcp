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
    /// Creates a new xcodebuild runner.
    public init() {}

    /// Executes an xcodebuild command with the given arguments.
    ///
    /// - Parameter arguments: The command-line arguments to pass to xcodebuild.
    /// - Returns: The result containing exit code and output.
    /// - Throws: An error if the process fails to launch.
    public func run(arguments: [String]) async throws -> XcodebuildResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = ["xcodebuild"] + arguments

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            do {
                try process.run()
                process.waitUntilExit()

                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                let result = XcodebuildResult(
                    exitCode: process.terminationStatus,
                    stdout: stdout,
                    stderr: stderr
                )
                continuation.resume(returning: result)
            } catch {
                continuation.resume(throwing: error)
            }
        }
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
