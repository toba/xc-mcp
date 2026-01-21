import Foundation

/// Wrapper for executing Swift commands.
///
/// `SwiftRunner` provides a Swift interface for invoking the Swift command-line
/// tools. It supports building, testing, and running Swift packages.
///
/// ## Example
///
/// ```swift
/// let runner = SwiftRunner()
///
/// // Build a package
/// let result = try await runner.build(
///     packagePath: "/path/to/package",
///     configuration: "debug"
/// )
///
/// // Run tests
/// try await runner.test(packagePath: "/path/to/package")
/// ```
public struct SwiftRunner: Sendable {
    /// Creates a new Swift runner.
    public init() {}

    /// Executes a swift command with the given arguments.
    ///
    /// - Parameters:
    ///   - arguments: The command-line arguments to pass to swift.
    ///   - workingDirectory: Optional working directory for the command.
    /// - Returns: The result containing exit code and output.
    /// - Throws: An error if the process fails to launch.
    public func run(arguments: [String], workingDirectory: String? = nil) async throws
        -> SwiftResult
    {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
            process.arguments = arguments

            if let workingDirectory {
                process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
            }

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

                let result = SwiftResult(
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

    /// Builds a Swift package.
    ///
    /// - Parameters:
    ///   - packagePath: Path to the Swift package directory.
    ///   - configuration: Build configuration ("debug" or "release"). Defaults to "debug".
    ///   - product: Optional specific product to build.
    /// - Returns: The build result containing exit code and output.
    public func build(
        packagePath: String,
        configuration: String = "debug",
        product: String? = nil
    ) async throws -> SwiftResult {
        var args = ["build", "-c", configuration]
        if let product {
            args.append(contentsOf: ["--product", product])
        }
        return try await run(arguments: args, workingDirectory: packagePath)
    }

    /// Runs tests for a Swift package.
    ///
    /// - Parameters:
    ///   - packagePath: Path to the Swift package directory.
    ///   - filter: Optional test filter pattern.
    /// - Returns: The test result containing exit code and output.
    public func test(
        packagePath: String,
        filter: String? = nil
    ) async throws -> SwiftResult {
        var args = ["test"]
        if let filter {
            args.append(contentsOf: ["--filter", filter])
        }
        return try await run(arguments: args, workingDirectory: packagePath)
    }

    /// Runs a Swift package executable.
    ///
    /// - Parameters:
    ///   - packagePath: Path to the Swift package directory.
    ///   - executableName: Optional name of the executable to run.
    ///   - arguments: Arguments to pass to the executable.
    /// - Returns: The run result containing exit code and output.
    public func runExecutable(
        packagePath: String,
        executableName: String? = nil,
        arguments: [String] = []
    ) async throws -> SwiftResult {
        var args = ["run"]
        if let executableName {
            args.append(executableName)
        }
        if !arguments.isEmpty {
            args.append("--")
            args.append(contentsOf: arguments)
        }
        return try await run(arguments: args, workingDirectory: packagePath)
    }

    /// Cleans build artifacts for a Swift package.
    ///
    /// - Parameter packagePath: Path to the Swift package directory.
    /// - Returns: The clean result containing exit code and output.
    public func clean(packagePath: String) async throws -> SwiftResult {
        try await run(arguments: ["package", "clean"], workingDirectory: packagePath)
    }

    /// Shows package dependencies.
    ///
    /// - Parameter packagePath: Path to the Swift package directory.
    /// - Returns: The result containing dependency tree.
    public func showDependencies(packagePath: String) async throws -> SwiftResult {
        try await run(arguments: ["package", "show-dependencies"], workingDirectory: packagePath)
    }

    /// Resolves package dependencies.
    ///
    /// - Parameter packagePath: Path to the Swift package directory.
    /// - Returns: The resolve result containing exit code and output.
    public func resolve(packagePath: String) async throws -> SwiftResult {
        try await run(arguments: ["package", "resolve"], workingDirectory: packagePath)
    }

    /// Updates package dependencies to their latest versions.
    ///
    /// - Parameter packagePath: Path to the Swift package directory.
    /// - Returns: The update result containing exit code and output.
    public func update(packagePath: String) async throws -> SwiftResult {
        try await run(arguments: ["package", "update"], workingDirectory: packagePath)
    }
}
